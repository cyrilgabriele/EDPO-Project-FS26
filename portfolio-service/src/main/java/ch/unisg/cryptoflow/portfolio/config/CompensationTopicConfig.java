package ch.unisg.cryptoflow.portfolio.config;

import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;

@Configuration
public class CompensationTopicConfig {

    @Bean
    public NewTopic portfolioCompensationTopic(
        @Value("${crypto.kafka.topic.portfolio-compensation}") String topicName
    ) {
        return TopicBuilder.name(topicName)
            .partitions(3)
            .replicas(1)
            .build();
    }

    @Bean
    public NewTopic userCompensationTopic(
        @Value("${crypto.kafka.topic.user-compensation}") String topicName
    ) {
        return TopicBuilder.name(topicName)
            .partitions(3)
            .replicas(1)
            .build();
    }
}
