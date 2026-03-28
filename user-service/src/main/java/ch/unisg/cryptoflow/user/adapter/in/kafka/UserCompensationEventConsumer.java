package ch.unisg.cryptoflow.user.adapter.in.kafka;

import ch.unisg.cryptoflow.events.UserCompensationRequestedEvent;
import ch.unisg.cryptoflow.user.application.port.in.CompensateUserUseCase;
import ch.unisg.cryptoflow.user.application.port.out.LoadUserPort;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;

@Slf4j
@Component
@RequiredArgsConstructor
public class UserCompensationEventConsumer {

    private static final Duration CREATION_WAIT_TIMEOUT = Duration.ofSeconds(5);
    private static final Duration CREATION_POLL_INTERVAL = Duration.ofMillis(200);

    private final CompensateUserUseCase compensateUserUseCase;
    private final LoadUserPort loadUserPort;

    @KafkaListener(
        topics = "${crypto.kafka.topic.user-compensation}",
        containerFactory = "userCompensationKafkaListenerContainerFactory"
    )
    public void onUserCompensation(UserCompensationRequestedEvent event) {
        if (event == null || event.userId() == null) {
            log.warn("Received invalid user compensation event: {}", event);
            return;
        }

        String userId = event.userId();
        if (!waitForUserCreation(userId)) {
            log.info("User {} not found for compensation request; skipping", userId);
            return;
        }

        boolean deleted = compensateUserUseCase.compensateUser(userId);
        if (deleted) {
            log.info("Deleted user {} in response to portfolio compensation request", userId);
        } else {
            log.warn("User {} already absent when processing portfolio compensation request", userId);
        }
    }

    private boolean waitForUserCreation(String userId) {
        Instant deadline = Instant.now().plus(CREATION_WAIT_TIMEOUT);
        while (Instant.now().isBefore(deadline)) {
            if (loadUserPort.loadUser(userId).isPresent()) {
                return true;
            }
            sleep();
        }
        return loadUserPort.loadUser(userId).isPresent();
    }

    private void sleep() {
        try {
            Thread.sleep(CREATION_POLL_INTERVAL.toMillis());
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while waiting for user creation", ex);
        }
    }
}
