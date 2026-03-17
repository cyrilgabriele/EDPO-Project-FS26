package ch.unisg.cryptoflow.userservice.adapter.in.worker;

import ch.unisg.cryptoflow.userservice.application.port.in.CreateUserCommand;
import ch.unisg.cryptoflow.userservice.application.port.in.CreateUserUseCase;
import ch.unisg.cryptoflow.userservice.domain.User;
import ch.unisg.cryptoflow.userservice.payload.UserCreationContext;
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

    private final CreateUserUseCase createUserUseCase;

    @JobWorker(type="userCreationWorker")
    public void handleCreateUserRequest(JobClient client, ActivatedJob job) {
        log.info("Service Task started via Worker");
        Map<String, Object> variables = job.getVariablesAsMap();
        UserCreationContext userCreationContext = UserCreationContext.fromMap(variables);

        Object userIdVariable = variables.get("userId");
        if (userIdVariable == null) {
            throw new IllegalStateException("UserId variable missing for user creation job " + job.getKey());
        }
        String userId = userIdVariable.toString();

        CreateUserCommand command = new CreateUserCommand(userId, userCreationContext.userName(), userCreationContext.password(), userCreationContext.email());
        User user = createUserUseCase.createUser(command);

        log.info("Persisted user {} with userId {} and email {}", user.username(), user.userId(), user.email());
        client.newCompleteCommand(job.getKey())
                .send().join();
    }
}
