package ch.unisg.cryptoflow.user.config;

import ch.unisg.cryptoflow.events.PortfolioCompensationRequestedEvent;
import ch.unisg.cryptoflow.events.UserCompensationRequestedEvent;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.annotation.EnableKafka;
import org.springframework.kafka.config.ConcurrentKafkaListenerContainerFactory;
import org.springframework.kafka.core.ConsumerFactory;
import org.springframework.kafka.core.DefaultKafkaConsumerFactory;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.core.ProducerFactory;
import org.springframework.kafka.support.serializer.JsonDeserializer;
import org.springframework.kafka.support.serializer.JsonSerializer;

import java.util.HashMap;
import java.util.Map;

@Configuration
@EnableKafka
public class KafkaCompensationConfig {

    @Value("${spring.kafka.bootstrap-servers}")
    private String bootstrapServers;

    @Bean
    public ProducerFactory<String, PortfolioCompensationRequestedEvent> portfolioCompensationProducerFactory() {
        Map<String, Object> props = new HashMap<>();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);
        props.put(JsonSerializer.ADD_TYPE_INFO_HEADERS, false);
        return new DefaultKafkaProducerFactory<>(props);
    }

    @Bean
    public KafkaTemplate<String, PortfolioCompensationRequestedEvent> portfolioCompensationKafkaTemplate(
        ProducerFactory<String, PortfolioCompensationRequestedEvent> portfolioCompensationProducerFactory
    ) {
        return new KafkaTemplate<>(portfolioCompensationProducerFactory);
    }

    @Bean
    public ConsumerFactory<String, UserCompensationRequestedEvent> userCompensationConsumerFactory() {
        JsonDeserializer<UserCompensationRequestedEvent> deserializer =
            new JsonDeserializer<>(UserCompensationRequestedEvent.class, false);
        deserializer.addTrustedPackages("ch.unisg.cryptoflow.events");
        Map<String, Object> props = new HashMap<>();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, "user-service-compensation-listener");
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
        return new DefaultKafkaConsumerFactory<>(props, new StringDeserializer(), deserializer);
    }

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, UserCompensationRequestedEvent>
    userCompensationKafkaListenerContainerFactory() {
        ConcurrentKafkaListenerContainerFactory<String, UserCompensationRequestedEvent> factory =
            new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(userCompensationConsumerFactory());
        return factory;
    }
}
