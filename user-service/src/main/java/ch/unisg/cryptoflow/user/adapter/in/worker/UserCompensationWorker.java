package ch.unisg.cryptoflow.user.adapter.in.worker;

import ch.unisg.cryptoflow.user.adapter.out.kafka.PortfolioCompensationProducer;
import ch.unisg.cryptoflow.user.application.port.in.CompensateUserUseCase;
import io.camunda.zeebe.client.api.response.ActivatedJob;
import io.camunda.zeebe.client.api.worker.JobClient;
import io.camunda.zeebe.spring.client.annotation.JobWorker;
import java.util.HashMap;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class UserCompensationWorker {

    private final CompensateUserUseCase compensateUserUseCase;
    private final PortfolioCompensationProducer portfolioCompensationProducer;

    @JobWorker(type = "userCompensationWorker")
    public void compensateUser(JobClient client, ActivatedJob job) {
        Map<String, Object> variables = job.getVariablesAsMap();
        String userId = requireString(variables, "userId");
        String userName = asNullableString(variables.get("userName"));
        String email = asNullableString(variables.get("e_mail"));
        Long portfolioId = parseOptionalLong(variables.get("portfolioId"));

        boolean userDeleted = compensateUserUseCase.compensateUser(userId);
        if (userDeleted) {
            log.info("Compensated user {} after onboarding failure", userId);
        } else {
            log.warn("Unable to delete user {} during compensation; record not found", userId);
        }

        portfolioCompensationProducer.publishPortfolioDeletion(
            userId,
            userName,
            portfolioId,
            "User compensation job %d requested portfolio rollback".formatted(job.getKey())
        );

        Map<String, Object> updates = new HashMap<>();
        updates.put("isUserCreated", userDeleted ? Boolean.FALSE : Boolean.TRUE);
        client.newCompleteCommand(job.getKey())
            .variables(updates)
            .send()
            .join();
    }

    private String requireString(Map<String, Object> variables, String key) {
        Object value = variables.get(key);
        if (value == null) {
            throw new IllegalStateException(key + " variable missing for user compensation job");
        }
        return value.toString();
    }

    private Long parseOptionalLong(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Number number) {
            return number.longValue();
        }
        try {
            return Long.parseLong(value.toString());
        } catch (NumberFormatException ex) {
            log.warn("Unable to parse portfolioId variable {} as long", value);
            return null;
        }
    }

    private String asNullableString(Object value) {
        return value != null ? value.toString() : null;
    }
}
