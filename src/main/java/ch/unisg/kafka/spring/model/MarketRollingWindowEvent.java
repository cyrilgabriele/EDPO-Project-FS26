package ch.unisg.kafka.spring.model;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Instant;

/**
 * Internal event envelope published to Kafka.
 */
public record MarketRollingWindowEvent(
        @JsonProperty("source") String source,
        @JsonProperty("window") String window,
        @JsonProperty("eventTime") Instant eventTime,
        @JsonProperty("ticker") BinanceRollingWindowTicker ticker
) {
    public String symbol() {
        return ticker.symbol();
    }
}
