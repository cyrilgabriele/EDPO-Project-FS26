package ch.unisg.cryptoflow.marketdata.adapter.out.kafka;

import ch.unisg.cryptoflow.events.CryptoPriceUpdatedEvent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

/**
 * Kafka producer adapter – publishes {@link CryptoPriceUpdatedEvent} messages
 * to the {@code crypto.price.raw} topic.
 *
 * <p>The trading symbol is used as the message key to guarantee partition
 * affinity: all events for a given symbol always land on the same partition,
 * preserving per-symbol ordering.
 */
@Component
public class CryptoPriceKafkaProducer {

    private static final Logger log = LoggerFactory.getLogger(CryptoPriceKafkaProducer.class);

    private final KafkaTemplate<String, CryptoPriceUpdatedEvent> kafkaTemplate;
    private final String topic;

    @SuppressWarnings("unchecked")
    public CryptoPriceKafkaProducer(
            KafkaTemplate<String, ?> kafkaTemplate,
            @Value("${crypto.kafka.topic.price-raw}") String topic) {
        this.kafkaTemplate = (KafkaTemplate<String, CryptoPriceUpdatedEvent>) kafkaTemplate;
        this.topic = topic;
    }

    public void publish(CryptoPriceUpdatedEvent event) {
        kafkaTemplate.send(topic, event.symbol(), event)
                .whenComplete((result, ex) -> {
                    if (ex != null) {
                        log.error("Failed to publish price event for symbol {}", event.symbol(), ex);
                    } else {
                        log.debug("Published price event for {} → partition={} offset={}",
                                event.symbol(),
                                result.getRecordMetadata().partition(),
                                result.getRecordMetadata().offset());
                    }
                });
    }
}
