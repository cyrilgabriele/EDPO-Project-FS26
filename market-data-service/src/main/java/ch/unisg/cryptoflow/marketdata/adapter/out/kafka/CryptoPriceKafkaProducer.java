package ch.unisg.cryptoflow.marketdata.adapter.out.kafka;

import ch.unisg.cryptoflow.events.CryptoPriceUpdatedEvent;
import ch.unisg.cryptoflow.marketdata.application.EventLog;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

/**
 * Kafka producer adapter – publishes {@link CryptoPriceUpdatedEvent} messages
 * to the {@code crypto.price.raw} topic.
 *
 * <p>The trading symbol is used as the message key. Partitions are assigned
 * using round-robin by symbol index ({@code index % numPartitions}) rather
 * than Kafka's default Murmur2 hash. This guarantees even distribution
 * across partitions for a small, fixed set of symbols while still preserving
 * per-symbol ordering.
 */
@Component
public class CryptoPriceKafkaProducer {

    private static final Logger log = LoggerFactory.getLogger(CryptoPriceKafkaProducer.class);

    private final KafkaTemplate<String, CryptoPriceUpdatedEvent> kafkaTemplate;
    private final String topic;
    private final EventLog eventLog;
    private final int numPartitions;
    private final Map<String, Integer> symbolPartitionMap;

    @SuppressWarnings("unchecked")
    public CryptoPriceKafkaProducer(
            KafkaTemplate<String, ?> kafkaTemplate,
            @Value("${crypto.kafka.topic.price-raw}") String topic,
            @Value("${crypto.kafka.topic.price-raw-partitions:3}") int numPartitions,
            @Value("${binance.symbols}") List<String> symbols,
            EventLog eventLog) {
        this.kafkaTemplate = (KafkaTemplate<String, CryptoPriceUpdatedEvent>) kafkaTemplate;
        this.topic = topic;
        this.eventLog = eventLog;
        this.numPartitions = numPartitions;
        this.symbolPartitionMap = IntStream.range(0, symbols.size())
                .boxed()
                .collect(Collectors.toMap(symbols::get, i -> i % numPartitions));
        log.info("Symbol → partition mapping: {}", symbolPartitionMap);
    }

    public void publish(CryptoPriceUpdatedEvent event) {
        int partition = symbolPartitionMap.getOrDefault(event.symbol(), Math.abs(event.symbol().hashCode()) % numPartitions);
        kafkaTemplate.send(topic, partition, event.symbol(), event)
                .whenComplete((result, ex) -> {
                    if (ex != null) {
                        log.error("Failed to publish price event for symbol {}", event.symbol(), ex);
                    } else {
                        int actualPartition = result.getRecordMetadata().partition();
                        long offset = result.getRecordMetadata().offset();
                        log.debug("Published price event for {} → partition={} offset={}",
                                event.symbol(), actualPartition, offset);
                        eventLog.record(new EventLog.Entry(
                                event.eventId(),
                                event.symbol(),
                                event.price(),
                                event.timestamp(),
                                Instant.now(),
                                actualPartition,
                                offset
                        ));
                    }
                });
    }
}
