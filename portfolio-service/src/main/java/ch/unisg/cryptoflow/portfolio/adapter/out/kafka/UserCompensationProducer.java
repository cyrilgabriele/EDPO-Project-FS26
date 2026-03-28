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

    public void publishUserDeletion(String userId, String userName, String email, String reason) {
        UserCompensationRequestedEvent event = new UserCompensationRequestedEvent(userId, userName, email, reason);
        try {
            kafkaTemplate.send(topic, userId, event).get();
            log.info("Published user compensation request for user {}", userId);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while publishing user compensation", ex);
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to publish user compensation for user " + userId, ex);
        }
    }
}
