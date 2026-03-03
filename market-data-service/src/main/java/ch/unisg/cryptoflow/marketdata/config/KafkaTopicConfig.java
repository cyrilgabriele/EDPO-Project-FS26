package ch.unisg.cryptoflow.marketdata.config;

import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;

/**
 * Programmatic Kafka topic creation.
 *
 * <p>Spring Kafka's {@code KafkaAdmin} detects {@link NewTopic} beans at startup
 * and creates the topics if they do not yet exist, making the setup reproducible
 * without any manual Kafka CLI commands.
 */
@Configuration
public class KafkaTopicConfig {

    @Bean
    public NewTopic cryptoPriceRawTopic(
            @Value("${crypto.kafka.topic.price-raw}") String name) {
        return TopicBuilder.name(name)
                .partitions(3)
                .replicas(1)
                .build();
    }

    @Bean
    public NewTopic cryptoPriceRawDltTopic(
            @Value("${crypto.kafka.topic.price-raw-dlt}") String name) {
        return TopicBuilder.name(name)
                .partitions(1)
                .replicas(1)
                .build();
    }
}
