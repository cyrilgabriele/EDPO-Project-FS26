package ch.unisg.cryptoflow.portfolio.adapter.out.kafka;

import ch.unisg.cryptoflow.events.UserCompensationRequestedEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class UserCompensationProducer {

    private final KafkaTemplate<String, UserCompensationRequestedEvent> kafkaTemplate;

    @Value("${crypto.kafka.topic.user-compensation}")
    private String topic;

    public void publishUserDeletion(String userId, String reason) {
        UserCompensationRequestedEvent event = new UserCompensationRequestedEvent(userId, reason);
        kafkaTemplate.send(topic, userId, event);
        log.info("Published user compensation request for user {}", userId);
    }
}
