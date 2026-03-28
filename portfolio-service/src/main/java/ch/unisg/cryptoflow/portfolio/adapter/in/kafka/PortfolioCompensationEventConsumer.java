package ch.unisg.cryptoflow.portfolio.adapter.in.kafka;

import ch.unisg.cryptoflow.events.PortfolioCompensationRequestedEvent;
import ch.unisg.cryptoflow.portfolio.application.PortfolioService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;

@Slf4j
@Component
@RequiredArgsConstructor
public class PortfolioCompensationEventConsumer {

    private static final Duration CREATION_WAIT_TIMEOUT = Duration.ofSeconds(5);
    private static final Duration CREATION_POLL_INTERVAL = Duration.ofMillis(200);

    private final PortfolioService portfolioService;

    @KafkaListener(
        topics = "${crypto.kafka.topic.portfolio-compensation}",
        containerFactory = "portfolioCompensationKafkaListenerContainerFactory"
    )
    public void onPortfolioCompensation(PortfolioCompensationRequestedEvent event) {
        if (event == null || event.userId() == null) {
            log.warn("Received invalid portfolio compensation event: {}", event);
            return;
        }

        String userId = event.userId();
        if (!waitForPortfolioCreation(userId)) {
            log.info("Portfolio for {} not found when processing user compensation request; skipping", userId);
            return;
        }

        boolean deleted = portfolioService.deletePortfolioForUser(userId);
        if (deleted) {
            log.info("Deleted portfolio for user {} after compensation request", userId);
        } else {
            log.warn("Portfolio for user {} already removed before compensation consumer ran", userId);
        }
    }

    private boolean waitForPortfolioCreation(String userId) {
        Instant deadline = Instant.now().plus(CREATION_WAIT_TIMEOUT);
        while (Instant.now().isBefore(deadline)) {
            if (portfolioService.getPortfolio(userId).isPresent()) {
                return true;
            }
            sleep();
        }
        return portfolioService.getPortfolio(userId).isPresent();
    }

    private void sleep() {
        try {
            Thread.sleep(CREATION_POLL_INTERVAL.toMillis());
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while waiting for portfolio creation", ex);
        }
    }
}
