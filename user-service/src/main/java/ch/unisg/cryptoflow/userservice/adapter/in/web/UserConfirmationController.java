package ch.unisg.cryptoflow.userservice.adapter.in.web;

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

@Slf4j
@RestController
@RequestMapping("/user/confirm")
@RequiredArgsConstructor
public class UserConfirmationController {

    private final ZeebeClient zeebeClient;

    @GetMapping("/{userId}")
    public ResponseEntity<Map<String, Object>> confirmUser(@PathVariable String userId) {
        try {
            log.info("Received request to confirm user with id: {}", userId);
            zeebeClient.newPublishMessageCommand()
                .messageName("UserConfirmed")
                .correlationKey(userId)
                .variables(Map.of("UserId", userId, "mailConfirmed", true))
                .send()
                .join();

            log.info("Published UserConfirmed message for user {}", userId);
            return ResponseEntity.ok(Map.of(
                "status", "confirmed",
                "userId", userId,
                "message", "User confirmed successfully"
            ));
        } catch (Exception ex) {
            log.error("Failed to publish confirmation for user {}", userId, ex);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of(
                    "status", "error",
                    "userId", userId,
                    "message", "Unable to confirm user at this time"
                ));
        }
    }
}
