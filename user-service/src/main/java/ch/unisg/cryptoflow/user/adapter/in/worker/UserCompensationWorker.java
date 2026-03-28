package ch.unisg.cryptoflow.user.adapter.in.worker;

import ch.unisg.cryptoflow.user.application.port.in.CompensateUserUseCase;
import ch.unisg.cryptoflow.user.adapter.out.kafka.PortfolioCompensationProducer;
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
public class UserCompensationWorker {

    private final CompensateUserUseCase compensateUserUseCase;
    private final PortfolioCompensationProducer portfolioCompensationProducer;

    @JobWorker(type = "userCompensationWorker")
    public void compensateUser(JobClient client, ActivatedJob job) {
        Map<String, Object> variables = job.getVariablesAsMap();
        Object userIdValue = variables.get("userId");
        if (userIdValue == null) {
            throw new IllegalStateException("userId variable missing for user compensation job " + job.getKey());
        }

        String userId = userIdValue.toString();
        Boolean userCreatedFlag = parseOptionalBoolean(variables.get("isUserCreated"));
        Boolean portfolioCreatedFlag = parseOptionalBoolean(variables.get("isPortfolioCreated"));

        boolean userDeleted = compensateUserUseCase.compensateUser(userId);
        if (userDeleted) {
            log.info("Compensated user {} after onboarding failure", userId);
        } else if (!Boolean.FALSE.equals(userCreatedFlag)) {
            log.warn("Tried to compensate user {} but no persisted user was found", userId);
        } else {
            log.info("User creation for {} was reported as failed; no persisted user to delete", userId);
        }

        boolean shouldAttemptPortfolioDeletion = portfolioCreatedFlag == null || Boolean.TRUE.equals(portfolioCreatedFlag);
        if (shouldAttemptPortfolioDeletion) {
            portfolioCompensationProducer.publishPortfolioDeletion(
                userId,
                "User compensation task " + job.getKey() + " requested portfolio rollback"
            );
        } else {
            log.info("Portfolio creation flagged as failed for {}; skipping portfolio compensation", userId);
        }

        client.newCompleteCommand(job.getKey()).send().join();
    }

    private Boolean parseOptionalBoolean(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Boolean boolValue) {
            return boolValue;
        }
        return Boolean.parseBoolean(value.toString());
    }

}
