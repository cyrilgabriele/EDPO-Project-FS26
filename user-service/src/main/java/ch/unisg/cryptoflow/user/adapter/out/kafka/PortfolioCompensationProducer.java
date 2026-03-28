package ch.unisg.cryptoflow.user.adapter.out.kafka;

import ch.unisg.cryptoflow.events.PortfolioCompensationRequestedEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class PortfolioCompensationProducer {

    private final KafkaTemplate<String, PortfolioCompensationRequestedEvent> kafkaTemplate;

    @Value("${crypto.kafka.topic.portfolio-compensation}")
    private String topic;

    public void publishPortfolioDeletion(String userId, String userName, Long portfolioId, String reason) {
        PortfolioCompensationRequestedEvent event = new PortfolioCompensationRequestedEvent(userId, userName, portfolioId, reason);
        try {
            kafkaTemplate.send(topic, userId, event).get();
            log.info("Published portfolio compensation request for user {} (portfolioId={})", userId, portfolioId);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while publishing portfolio compensation", ex);
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to publish portfolio compensation for user " + userId, ex);
        }
    }
}
