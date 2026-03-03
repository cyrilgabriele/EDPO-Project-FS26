package ch.unisg.cryptoflow.marketdata.domain;

import java.math.BigDecimal;

/**
 * Domain object representing a single price snapshot for one trading symbol,
 * as returned by the Binance REST API.
 */
public record PriceTick(String symbol, BigDecimal price) {}
