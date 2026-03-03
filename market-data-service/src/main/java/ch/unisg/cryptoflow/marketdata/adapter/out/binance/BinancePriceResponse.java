package ch.unisg.cryptoflow.marketdata.adapter.out.binance;

import java.math.BigDecimal;

/**
 * DTO matching a single entry in the Binance REST response for
 * {@code GET /api/v3/ticker/price?symbols=[...]}.
 *
 * <p>Example JSON: {@code {"symbol":"BTCUSDT","price":"50000.00"}}
 */
public record BinancePriceResponse(String symbol, BigDecimal price) {}
