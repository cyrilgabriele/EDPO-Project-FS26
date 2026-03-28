package ch.unisg.cryptoflow.portfolio.adapter.in.worker;

import ch.unisg.cryptoflow.portfolio.application.PortfolioCreationResult;
import ch.unisg.cryptoflow.portfolio.application.PortfolioService;
import io.camunda.zeebe.client.api.response.ActivatedJob;
import io.camunda.zeebe.client.api.worker.JobClient;
import io.camunda.zeebe.spring.client.annotation.JobWorker;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class PortfolioCreationWorker {

    private static final String PORTFOLIO_COMPENSATION_TRIGGER = "TRIGGER_PORTFOLIO_COMPENSATION";

    private final PortfolioService portfolioService;

    @JobWorker(type = "portfolioCreationWorker")
    public void createPortfolio(JobClient client, ActivatedJob job) {
        var variables = job.getVariablesAsMap();
        String userId = null;
        String userName = null;
        boolean portfolioCreated = false;
        Long portfolioId = null;

        try {
            Object userIdValue = variables.get("userId");
            Object userNameValue = variables.get("userName");
            if (userIdValue == null || userNameValue == null) {
                log.error("Missing {} for portfolio creation job {}", userIdValue == null ? "userId" : "userName", job.getKey());
            } else {
                userId = userIdValue.toString();
                userName = userNameValue.toString();

                failIfCompensationTrigger(userName);
                PortfolioCreationResult result = portfolioService.createPortfolioForUser(userId, userName);
                portfolioCreated = result.created();
                portfolioId = result.portfolioId();
                log.info("Ensured portfolio {} for user {} (created={})", result.portfolioId(), userId, result.created());
            }
        } catch (IntentionalCompensationTriggerException ex) {
            log.warn("Portfolio creation intentionally aborted for {} to test compensation", fallbackUserId(variables, userId));
            portfolioCreated = false;
        } catch (IllegalStateException ex) {
            log.error("Portfolio creation failed for {} before persisting portfolio: {}", fallbackUserId(variables, userId), ex.getMessage());
            portfolioCreated = false;
        }

        Map<String, Object> completionVars = new HashMap<>();
        if (portfolioId != null) {
            completionVars.put("portfolioId", portfolioId);
        }
        completionVars.put("portfolioCreated", portfolioCreated);
        completionVars.put("isPortfolioCreated", portfolioCreated);

        client.newCompleteCommand(job.getKey())
            .variables(completionVars)
            .send()
            .join();
    }

    private void failIfCompensationTrigger(String userName) {
        if (userName != null && PORTFOLIO_COMPENSATION_TRIGGER.equalsIgnoreCase(userName)) {
            throw new IntentionalCompensationTriggerException();
        }
    }

    private String fallbackUserId(Map<String, Object> variables, String resolvedUserId) {
        if (resolvedUserId != null) {
            return resolvedUserId;
        }
        Object userIdValue = variables.get("userId");
        return userIdValue != null ? userIdValue.toString() : "<unknown-user>";
    }

    private static final class IntentionalCompensationTriggerException extends RuntimeException { }
}
