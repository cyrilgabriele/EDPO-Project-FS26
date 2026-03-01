package ch.unisg.kafka.spring.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.math.BigDecimal;

/**
 * Represents a single symbol delta emitted by Binance's all market rolling window statistics stream.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public record BinanceRollingWindowTicker(
        @JsonProperty("e") String eventType,
        @JsonProperty("E") long eventTime,
        @JsonProperty("s") String symbol,
        @JsonProperty("p") BigDecimal priceChange,
        @JsonProperty("P") BigDecimal priceChangePercent,
        @JsonProperty("w") BigDecimal weightedAveragePrice,
        @JsonProperty("x") BigDecimal firstTradePrice,
        @JsonProperty("c") BigDecimal closePrice,
        @JsonProperty("Q") BigDecimal closeQuantity,
        @JsonProperty("b") BigDecimal bestBidPrice,
        @JsonProperty("B") BigDecimal bestBidQuantity,
        @JsonProperty("a") BigDecimal bestAskPrice,
        @JsonProperty("A") BigDecimal bestAskQuantity,
        @JsonProperty("o") BigDecimal openPrice,
        @JsonProperty("h") BigDecimal highPrice,
        @JsonProperty("l") BigDecimal lowPrice,
        @JsonProperty("v") BigDecimal baseAssetVolume,
        @JsonProperty("q") BigDecimal quoteAssetVolume,
        @JsonProperty("O") long statisticsOpenTime,
        @JsonProperty("C") long statisticsCloseTime,
        @JsonProperty("F") long firstTradeId,
        @JsonProperty("L") long lastTradeId,
        @JsonProperty("n") long totalNumberOfTrades
) {
}
