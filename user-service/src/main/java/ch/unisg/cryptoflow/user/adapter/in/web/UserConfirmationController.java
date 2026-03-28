package ch.unisg.cryptoflow.user.adapter.in.web;

import ch.unisg.cryptoflow.user.application.service.ConfirmationLinkService;
import ch.unisg.cryptoflow.user.domain.ConfirmationLinkStatus;
import io.camunda.zeebe.client.ZeebeClient;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.Optional;

@Slf4j
@RestController
@RequestMapping("/user/confirm")
@RequiredArgsConstructor
public class UserConfirmationController {

    private final ZeebeClient zeebeClient;
    private final ConfirmationLinkService confirmationLinkService;

    @GetMapping("/{userId}")
    public ResponseEntity<Map<String, Object>> confirmUser(@PathVariable String userId) {
        try {
            log.info("Received request to confirm user with id: {}", userId);

            Optional<ConfirmationLinkStatus> currentStatus = confirmationLinkService.getStatus(userId);
            if (currentStatus.isEmpty()) {
                log.warn("Received confirmation for unknown user id {}", userId);
                return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(Map.of(
                        "status", "not_found",
                        "userId", userId,
                        "message", "No pending confirmation found"
                    ));
            }

            ConfirmationLinkStatus status = currentStatus.get();
            if (status == ConfirmationLinkStatus.INVALIDATED) {
                log.info("Confirmation attempt for expired link {}", userId);
                return ResponseEntity.status(HttpStatus.GONE)
                    .body(Map.of(
                        "status", "expired",
                        "userId", userId,
                        "message", "Confirmation link has expired"
                    ));
            }

            if (status == ConfirmationLinkStatus.CONFIRMED) {
                log.info("Confirmation attempt for already confirmed user {}", userId);
                return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of(
                        "status", "already_confirmed",
                        "userId", userId,
                        "message", "User already confirmed"
                    ));
            }

            if (!confirmationLinkService.confirmLink(userId)) {
                log.warn("Failed to transition confirmation state for user {}", userId);
                return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of(
                        "status", "confirmation_conflict",
                        "userId", userId,
                        "message", "Unable to confirm user at this time"
                    ));
            }

            zeebeClient.newPublishMessageCommand()
                .messageName("UserConfirmedEvent")
                .correlationKey(userId)
                .variables(Map.of("userId", userId, "mailConfirmed", true))
                .send()
                .join();

            log.info("Published UserConfirmedEvent message for user {}", userId);
            return ResponseEntity.ok(Map.of(
                "status", "confirmed",
                "userId", userId,
                "message", "User confirmed successfully"
            ));
        } catch (Exception ex) {
            log.error("Failed to publish confirmation for user {}", userId, ex);
            confirmationLinkService.revertConfirmation(userId);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of(
                    "status", "error",
                    "userId", userId,
                    "message", "Unable to confirm user at this time"
                ));
        }
    }
}
