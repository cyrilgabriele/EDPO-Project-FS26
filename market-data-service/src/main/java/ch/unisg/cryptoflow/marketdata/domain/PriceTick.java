package ch.unisg.cryptoflow.marketdata.domain;

import java.math.BigDecimal;

/**
 * Domain object representing a single price snapshot for one trading symbol,
 * as received from the Binance WebSocket ticker stream.
 */
public record PriceTick(String symbol, BigDecimal price) {}
