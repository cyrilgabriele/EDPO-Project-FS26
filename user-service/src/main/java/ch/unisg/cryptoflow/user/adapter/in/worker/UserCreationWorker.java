package ch.unisg.cryptoflow.user.adapter.in.worker;

import ch.unisg.cryptoflow.user.application.UserCreationResult;
import ch.unisg.cryptoflow.user.application.port.in.CreateUserCommand;
import ch.unisg.cryptoflow.user.application.port.in.CreateUserUseCase;
import ch.unisg.cryptoflow.user.payload.UserCreationContext;
import io.camunda.zeebe.client.api.response.ActivatedJob;
import io.camunda.zeebe.client.api.worker.JobClient;
import io.camunda.zeebe.spring.client.annotation.JobWorker;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class UserCreationWorker {

    private static final String USER_COMPENSATION_TRIGGER = "TRIGGER_USER_COMPENSATION";

    private final CreateUserUseCase createUserUseCase;

    @JobWorker(type="userCreationWorker")
    public void handleCreateUserRequest(JobClient client, ActivatedJob job) {
        log.info("Service Task started via Worker");
        Map<String, Object> variables = job.getVariablesAsMap();
        UserCreationContext userCreationContext = UserCreationContext.fromMap(variables);

        String userId = null;
        boolean userCreated = false;

        try {
            Object userIdVariable = variables.get("userId");
            if (userIdVariable == null) {
                throw new IllegalStateException("UserId variable missing for user creation job " + job.getKey());
            }
            userId = userIdVariable.toString();
            failIfCompensationTrigger(userCreationContext.userName());
            CreateUserCommand command = new CreateUserCommand(userId, userCreationContext.userName(), userCreationContext.password(), userCreationContext.email());
            UserCreationResult result = createUserUseCase.createUser(command);

            if (result.created()) {
                log.info("Persisted user {} with userId {} and email {}", result.user().username(), result.user().userId(), result.user().email());
            } else {
                log.warn("Skipped user creation for {} because a user already exists", userId);
            }
            userCreated = result.created();
        } catch (IntentionalCompensationTriggerException ex) {
            log.warn("User creation intentionally aborted for {} to test compensation", fallbackUserId(variables, userId));
            userCreated = false;
        } catch (IllegalStateException ex) {
            log.error("User creation failed for {} before persisting user: {}", fallbackUserId(variables, userId), ex.getMessage());
            userCreated = false;
        }

        client.newCompleteCommand(job.getKey())
            .variables(Map.of("isUserCreated", userCreated))
            .send()
            .join();
    }

    private String fallbackUserId(Map<String, Object> variables, String resolvedUserId) {
        if (resolvedUserId != null) {
            return resolvedUserId;
        }
        Object userIdVariable = variables.get("userId");
        return userIdVariable != null ? userIdVariable.toString() : "<unknown-user>";
    }

    private void failIfCompensationTrigger(String userName) {
        if (userName != null && USER_COMPENSATION_TRIGGER.equalsIgnoreCase(userName)) {
            throw new IntentionalCompensationTriggerException();
        }
    }

    private static final class IntentionalCompensationTriggerException extends RuntimeException { }
}
