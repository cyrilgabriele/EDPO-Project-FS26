package ch.unisg.cryptoflow.onboardingservice;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Thin client for the Camunda Operate REST API.
 *
 * Authenticates via client-credentials OAuth2 and caches the token until
 * 30 seconds before expiry. Queries process instances and variables for the
 * onboarding dashboard.
 */
@Slf4j
@Component
public class OperateApiClient {

    private static final String AUTH_URL    = "https://login.cloud.camunda.io/oauth/token";
    private static final String AUDIENCE    = "operate.camunda.io";
    private static final String PROCESS_ID  = "Process_10xcujt";

    private final RestTemplate rest = new RestTemplate();

    // Dedicated Operate credentials — must have the Operate scope in Camunda Console.
    // Can be the same client as the Zeebe credentials if that client has both scopes.
    @Value("${operate.client-id}")
    private String clientId;

    @Value("${operate.client-secret}")
    private String clientSecret;

    @Value("${camunda.client.cluster-id}")
    private String clusterId;

    @Value("${camunda.client.region}")
    private String region;

    private String tokenCache;
    private Instant tokenExpiresAt = Instant.EPOCH;

    // Cached process definition key for the latest deployed version.
    // Fetched once and reused — the definition key only changes on redeployment.
    private Long latestProcessDefinitionKey;

    // ── OAuth2 ────────────────────────────────────────────────────────────────

    private synchronized String token() {
        if (tokenCache != null && Instant.now().isBefore(tokenExpiresAt.minusSeconds(30))) {
            return tokenCache;
        }

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);

        MultiValueMap<String, String> body = new LinkedMultiValueMap<>();
        body.add("grant_type",   "client_credentials");
        body.add("client_id",    clientId);
        body.add("client_secret", clientSecret);
        body.add("audience",     AUDIENCE);

        @SuppressWarnings("unchecked")
        Map<String, Object> resp = rest.postForObject(
                AUTH_URL, new HttpEntity<>(body, headers), Map.class);

        tokenCache = (String) resp.get("access_token");
        int expiresIn = ((Number) resp.get("expires_in")).intValue();
        tokenExpiresAt = Instant.now().plusSeconds(expiresIn);
        log.debug("Refreshed Operate token, expires in {}s", expiresIn);
        return tokenCache;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private String baseUrl() {
        return "https://" + region + ".operate.camunda.io/" + clusterId + "/v1";
    }

    private HttpEntity<Map<String, Object>> json(Map<String, Object> body) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setBearerAuth(token());
        return new HttpEntity<>(body, headers);
    }

    // ── API calls ─────────────────────────────────────────────────────────────

    /**
     * Returns the key of the latest deployed version of the User Onboarding process.
     * Result is cached in memory — definition key only changes on redeployment.
     */
    @SuppressWarnings("unchecked")
    private synchronized long latestProcessDefinitionKey() {
        if (latestProcessDefinitionKey != null) return latestProcessDefinitionKey;

        Map<String, Object> body = Map.of(
                "filter", Map.of("bpmnProcessId", PROCESS_ID),
                "size",   1,
                "sort",   List.of(Map.of("field", "version", "order", "DESC"))
        );

        ResponseEntity<Map> resp = rest.exchange(
                baseUrl() + "/process-definitions/search",
                HttpMethod.POST, json(body), Map.class);

        List<Map<String, Object>> items = (List<Map<String, Object>>) resp.getBody().get("items");
        if (items == null || items.isEmpty()) {
            throw new IllegalStateException("No process definition found for bpmnProcessId=" + PROCESS_ID);
        }

        latestProcessDefinitionKey = ((Number) items.get(0).get("key")).longValue();
        log.info("Latest process definition key for {}: {}", PROCESS_ID, latestProcessDefinitionKey);
        return latestProcessDefinitionKey;
    }

    /**
     * Returns the 20 most recent instances of the latest deployed version of the
     * User Onboarding process, ordered by start date descending.
     */
    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> recentInstances() {
        Map<String, Object> body = Map.of(
                "filter", Map.of("processDefinitionKey", latestProcessDefinitionKey()),
                "size",   20,
                "sort",   List.of(Map.of("field", "startDate", "order", "DESC"))
        );

        ResponseEntity<Map> resp = rest.exchange(
                baseUrl() + "/process-instances/search",
                HttpMethod.POST, json(body), Map.class);

        List<Map<String, Object>> items = (List<Map<String, Object>>) resp.getBody().get("items");
        return items != null ? items : List.of();
    }

    /**
     * Fetches a single named variable for each given process instance key and
     * returns a map of instanceKey → value.
     *
     * Queries Operate once per instance key (filtering by both name and
     * processInstanceKey) so we never miss a variable due to page-size limits
     * when filtering only by name across all instances.
     *
     * Operate stores values as JSON strings (e.g. {@code "\"alice\""} for the
     * string {@code alice}), so string values are unquoted before returning.
     */
    @SuppressWarnings("unchecked")
    public Map<Long, String> variableByName(String varName, List<Long> instanceKeys) {
        if (instanceKeys.isEmpty()) return Map.of();

        Map<Long, String> result = new java.util.LinkedHashMap<>();
        for (Long instanceKey : instanceKeys) {
            try {
                Map<String, Object> body = Map.of(
                        "filter", Map.of("name", varName, "processInstanceKey", instanceKey),
                        "size",   5
                );

                ResponseEntity<Map> resp = rest.exchange(
                        baseUrl() + "/variables/search",
                        HttpMethod.POST, json(body), Map.class);

                List<Map<String, Object>> items = (List<Map<String, Object>>) resp.getBody().get("items");
                if (items != null && !items.isEmpty()) {
                    result.put(instanceKey, unquote((String) items.get(0).get("value")));
                }
            } catch (Exception e) {
                log.warn("Could not fetch variable '{}' for instance {}: {}", varName, instanceKey, e.getMessage());
            }
        }
        return result;
    }

    /** Strip the surrounding JSON quotes that Operate adds to string variables. */
    private String unquote(String value) {
        if (value == null) return "";
        String t = value.trim();
        return (t.startsWith("\"") && t.endsWith("\"") && t.length() >= 2)
                ? t.substring(1, t.length() - 1)
                : t;
    }
}
