package ch.unisg.cryptoflow.marketdata.application;

import ch.unisg.cryptoflow.events.CryptoPriceUpdatedEvent;
import ch.unisg.cryptoflow.marketdata.domain.PriceTick;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.UUID;

/**
 * Maps a {@link PriceTick} domain object to a {@link CryptoPriceUpdatedEvent}
 * that can be published to Kafka.
 *
 * <p>Each event receives a freshly generated UUID {@code eventId} to enable
 * idempotent processing on the consumer side.
 */
@Component
public class PriceEventMapper {

    public CryptoPriceUpdatedEvent toEvent(PriceTick tick) {
        return new CryptoPriceUpdatedEvent(
                UUID.randomUUID().toString(),
                tick.symbol(),
                tick.price(),
                Instant.now()
        );
    }
}
