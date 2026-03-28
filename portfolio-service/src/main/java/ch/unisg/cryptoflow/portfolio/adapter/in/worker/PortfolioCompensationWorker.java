package ch.unisg.cryptoflow.portfolio.adapter.in.worker;

import ch.unisg.cryptoflow.portfolio.adapter.out.kafka.UserCompensationProducer;
import ch.unisg.cryptoflow.portfolio.application.PortfolioService;
import io.camunda.zeebe.client.api.response.ActivatedJob;
import io.camunda.zeebe.client.api.worker.JobClient;
import io.camunda.zeebe.spring.client.annotation.JobWorker;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class PortfolioCompensationWorker {

    private final PortfolioService portfolioService;
    private final UserCompensationProducer userCompensationProducer;

    private static final Duration CREATION_WAIT_TIMEOUT = Duration.ofSeconds(5);
    private static final Duration CREATION_POLL_INTERVAL = Duration.ofMillis(200);

    @JobWorker(type = "portfolioCompensationWorker")
    public void compensatePortfolio(JobClient client, ActivatedJob job) {
        Map<String, Object> variables = job.getVariablesAsMap();
        Object userIdValue = variables.get("userId");
        if (userIdValue == null) {
            throw new IllegalStateException("userId variable missing for portfolio compensation job " + job.getKey());
        }

        String userId = userIdValue.toString();
        Boolean portfolioCreatedFlag = parseOptionalBoolean(variables.get("isPortfolioCreated"));
        Boolean userCreatedFlag = parseOptionalBoolean(variables.get("isUserCreated"));

        boolean shouldAttemptPortfolioDeletion = portfolioCreatedFlag == null || Boolean.TRUE.equals(portfolioCreatedFlag);
        if (shouldAttemptPortfolioDeletion) {
            boolean deleted = deletePortfolioWithWait(userId, portfolioCreatedFlag == null);
            if (deleted) {
                log.info("Compensated portfolio for user {} after onboarding failure", userId);
            } else {
                log.warn("Unable to compensate portfolio for user {}; portfolio not found", userId);
            }
        } else {
            log.info("Portfolio creation flagged as failed for {}; no portfolio to compensate", userId);
        }

        boolean shouldAttemptUserDeletion = userCreatedFlag == null || Boolean.TRUE.equals(userCreatedFlag);
        if (shouldAttemptUserDeletion) {
            userCompensationProducer.publishUserDeletion(
                userId,
                "Portfolio compensation task " + job.getKey() + " requested user rollback"
            );
        } else {
            log.info("User creation flagged as failed for {}; skipping user compensation from portfolio worker", userId);
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


    private boolean deletePortfolioWithWait(String userId, boolean waitForCreation) {
        if (portfolioService.getPortfolio(userId).isEmpty()) {
            if (!waitForCreation) {
                return false;
            }
            log.info("Portfolio for {} not visible yet; waiting up to {} ms before deletion", userId,
                CREATION_WAIT_TIMEOUT.toMillis());
            if (!waitForPortfolioCreation(userId)) {
                return false;
            }
        }
        return portfolioService.deletePortfolioForUser(userId);
    }

    private boolean waitForPortfolioCreation(String userId) {
        long deadline = System.currentTimeMillis() + CREATION_WAIT_TIMEOUT.toMillis();
        while (System.currentTimeMillis() < deadline) {
            if (portfolioService.getPortfolio(userId).isPresent()) {
                return true;
            }
            try {
                Thread.sleep(CREATION_POLL_INTERVAL.toMillis());
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("Compensation wait interrupted", ex);
            }
        }
        return portfolioService.getPortfolio(userId).isPresent();
    }
}
