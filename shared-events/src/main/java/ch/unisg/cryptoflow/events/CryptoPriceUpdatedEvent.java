package ch.unisg.cryptoflow.events;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Published by {@code market-data-service} to topic {@code crypto.price.raw}.
 * Carries the latest price tick for one trading symbol.
 *
 * <p>Consumed by {@code portfolio-service} (and later by any additional service)
 * without requiring changes to the producer (Event Notification pattern).
 */
public record CryptoPriceUpdatedEvent(
        /** UUID – enables idempotent processing on the consumer side. */
        String eventId,
        /** Trading pair symbol, e.g. {@code BTCUSDT}. Used as the Kafka message key. */
        String symbol,
        /** Current price in USDT as reported by the Binance REST API. */
        BigDecimal price,
        /** Timestamp of the Binance API response (UTC). */
        Instant timestamp
) {}
