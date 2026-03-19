package ch.unisg.cryptoflow.user.adapter.in.worker;

import ch.unisg.cryptoflow.user.payload.UserCreationContext;
import io.camunda.zeebe.client.api.response.ActivatedJob;
import io.camunda.zeebe.client.api.worker.JobClient;
import io.camunda.zeebe.spring.client.annotation.JobWorker;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Slf4j
@Component
public class UserPreparationWorker {

    @Value("${user.confirmation.base-url:http://localhost:8084}")
    private String confirmationBaseUrl;

    @JobWorker(type = "userPreparationWorker")
    public void prepareUser(JobClient client, ActivatedJob job) {
        UserCreationContext context = UserCreationContext.fromMap(job.getVariablesAsMap());

        String userId = UUID.randomUUID().toString();
        String confirmationLink = buildConfirmationLink(userId);
        String mailContent = buildMailContent(context.userName(), confirmationLink);

        Map<String, Object> updates = new HashMap<>();
        updates.put("userId", userId);
        updates.put("userCreationMailContent", mailContent);

        log.info("Prepared user {} with email {} and confirmation link {}", context.userName(), context.email(), confirmationLink);
        client.newCompleteCommand(job.getKey())
            .variables(updates)
            .send()
            .join();
    }

    private String buildConfirmationLink(String userId) {
        if (confirmationBaseUrl.endsWith("/")) {
            return confirmationBaseUrl + "user/confirm/" + userId;
        }
        return confirmationBaseUrl + "/user/confirm/" + userId;
    }

    private String buildMailContent(String userName, String confirmationLink) {
        return "Hi " + userName + ",\n\n" +
            "Please confirm your CryptoFlow account by clicking the link below:\n" +
            confirmationLink + "\n\n" +
            "If you did not request this, you can ignore this email.";
    }
}
