package ch.unisg.cryptoflow.marketdata.adapter.in.scheduling;

import ch.unisg.cryptoflow.events.CryptoPriceUpdatedEvent;
import ch.unisg.cryptoflow.marketdata.adapter.out.binance.BinanceApiClient;
import ch.unisg.cryptoflow.marketdata.adapter.out.kafka.CryptoPriceKafkaProducer;
import ch.unisg.cryptoflow.marketdata.application.PriceEventMapper;
import ch.unisg.cryptoflow.marketdata.domain.PriceTick;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Scheduling adapter – drives the Binance polling loop.
 *
 * <p>On each tick, it fetches prices from the Binance REST API, maps them to
 * {@link CryptoPriceUpdatedEvent} objects, and publishes one event per symbol
 * to Kafka. If Binance is unavailable the cycle is silently skipped.
 *
 * <p>This demonstrates the <strong>Event Notification</strong> pattern:
 * the producer emits events with no knowledge of who consumes them.
 */
@Component
public class PricePollingScheduler {

    private static final Logger log = LoggerFactory.getLogger(PricePollingScheduler.class);

    private final BinanceApiClient binanceApiClient;
    private final PriceEventMapper priceEventMapper;
    private final CryptoPriceKafkaProducer kafkaProducer;

    public PricePollingScheduler(
            BinanceApiClient binanceApiClient,
            PriceEventMapper priceEventMapper,
            CryptoPriceKafkaProducer kafkaProducer) {
        this.binanceApiClient = binanceApiClient;
        this.priceEventMapper = priceEventMapper;
        this.kafkaProducer = kafkaProducer;
    }

    @Scheduled(fixedRateString = "${binance.poll-interval-ms:10000}")
    public void poll() {
        List<PriceTick> ticks = binanceApiClient.fetchPrices();

        if (ticks.isEmpty()) {
            log.warn("Polling cycle skipped – no price data received from Binance");
            return;
        }

        List<CryptoPriceUpdatedEvent> events = ticks.stream()
                .map(priceEventMapper::toEvent)
                .toList();

        events.forEach(kafkaProducer::publish);

        log.debug("Published {} price events to Kafka (symbols: {})",
                events.size(),
                events.stream().map(CryptoPriceUpdatedEvent::symbol).toList());
    }
}
