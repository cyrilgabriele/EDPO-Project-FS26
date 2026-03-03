package ch.unisg.cryptoflow.marketdata.adapter.out.binance;

import ch.unisg.cryptoflow.marketdata.domain.PriceTick;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;

import java.util.List;

/**
 * Adapter for the Binance public REST API.
 *
 * <p>Calls {@code GET /api/v3/ticker/price?symbols=[...]} to fetch the latest
 * price for each configured symbol. Returns an empty list on any failure so
 * the polling cycle is skipped gracefully without crashing the service.
 *
 * <p>No API key is required – the endpoint is public and rate-limited to
 * roughly one request per 10 s per IP, which is compatible with the default
 * polling interval.
 */
@Component
public class BinanceApiClient {

    private static final Logger log = LoggerFactory.getLogger(BinanceApiClient.class);
    private static final ParameterizedTypeReference<List<BinancePriceResponse>> RESPONSE_TYPE =
            new ParameterizedTypeReference<>() {};

    private final WebClient webClient;
    private final List<String> symbols;

    public BinanceApiClient(
            WebClient.Builder webClientBuilder,
            @Value("${binance.base-url}") String baseUrl,
            @Value("${binance.symbols}") List<String> symbols) {
        this.webClient = webClientBuilder.baseUrl(baseUrl).build();
        this.symbols = symbols;
    }

    /**
     * Fetches the latest prices for the configured symbols.
     *
     * @return list of {@link PriceTick} domain objects – empty if the API is unavailable
     */
    public List<PriceTick> fetchPrices() {
        if (symbols.isEmpty()) {
            log.warn("No symbols configured – skipping Binance API call");
            return List.of();
        }
        try {
            String symbolsJson = buildSymbolsParam(symbols);
            List<BinancePriceResponse> responses = webClient.get()
                    .uri(uriBuilder -> uriBuilder
                            .path("/api/v3/ticker/price")
                            .queryParam("symbols", symbolsJson)
                            .build())
                    .retrieve()
                    .bodyToMono(RESPONSE_TYPE)
                    .block();

            if (responses == null || responses.isEmpty()) {
                log.warn("Binance API returned no price data for symbols: {}", symbols);
                return List.of();
            }

            log.debug("Received {} price ticks from Binance", responses.size());
            return responses.stream()
                    .map(r -> new PriceTick(r.symbol(), r.price()))
                    .toList();

        } catch (Exception e) {
            log.warn("Binance API call failed – polling cycle will be skipped: {}", e.getMessage());
            return List.of();
        }
    }

    private String buildSymbolsParam(List<String> symbols) {
        return "[\"" + String.join("\",\"", symbols) + "\"]";
    }
}
