package ch.unisg.cryptoflow.onboardingservice;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Exposes live onboarding process-instance data for the dashboard page.
 *
 * Fetches the 20 most recent User Onboarding instances from Camunda Operate,
 * then enriches each with its userName, e_mail, and userId variables via two
 * additional batch variable queries.
 */
@Slf4j
@RestController
@RequestMapping("/api/dashboard")
@RequiredArgsConstructor
public class OnboardingDashboardController {

    private final OperateApiClient operateClient;

    @GetMapping
    public Map<String, Object> dashboard() {
        try {
            List<Map<String, Object>> instances = operateClient.recentInstances();

            List<Long> keys = instances.stream()
                    .map(i -> ((Number) i.get("key")).longValue())
                    .toList();

            Map<Long, String> userNames = operateClient.variableByName("userName", keys);
            Map<Long, String> emails    = operateClient.variableByName("e_mail",   keys);
            Map<Long, String> userIds   = operateClient.variableByName("userId",   keys);

            List<Map<String, Object>> enriched = instances.stream().map(i -> {
                long key = ((Number) i.get("key")).longValue();
                Map<String, Object> row = new HashMap<>();
                row.put("key",       String.valueOf(key));
                row.put("state",     i.getOrDefault("state", "UNKNOWN"));
                row.put("startDate", i.getOrDefault("startDate", ""));
                row.put("endDate",   i.getOrDefault("endDate",   ""));
                row.put("userName",  userNames.getOrDefault(key, ""));
                row.put("email",     emails.getOrDefault(key,    ""));
                row.put("userId",    userIds.getOrDefault(key,   ""));
                return (Map<String, Object>) row;
            }).toList();

            return Map.of(
                    "instances", enriched,
                    "total",     enriched.size(),
                    "error",     ""
            );
        } catch (Exception e) {
            log.error("Operate API call failed: {}", e.getMessage());
            return Map.of(
                    "instances", List.of(),
                    "total",     0,
                    "error",     e.getMessage() != null ? e.getMessage() : "unknown error"
            );
        }
    }
}
