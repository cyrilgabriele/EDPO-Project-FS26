package ch.unisg.cryptoflow.portfolio.adapter.in.worker;

import ch.unisg.cryptoflow.portfolio.adapter.out.kafka.UserCompensationProducer;
import ch.unisg.cryptoflow.portfolio.application.PortfolioService;
import io.camunda.zeebe.client.api.response.ActivatedJob;
import io.camunda.zeebe.client.api.worker.JobClient;
import io.camunda.zeebe.spring.client.annotation.JobWorker;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class PortfolioCompensationWorker {

    private static final Duration CREATION_WAIT_TIMEOUT = Duration.ofSeconds(5);
    private static final Duration CREATION_POLL_INTERVAL = Duration.ofMillis(200);

    private final PortfolioService portfolioService;
    private final UserCompensationProducer userCompensationProducer;

    @JobWorker(type = "portfolioCompensationWorker")
    public void compensatePortfolio(JobClient client, ActivatedJob job) {
        Map<String, Object> variables = job.getVariablesAsMap();
        String userId = requireString(variables, "userId");
        String userName = asNullableString(variables.get("userName"));
        String email = asNullableString(variables.get("e_mail"));

        boolean portfolioDeleted = deletePortfolioWithWait(userId);
        if (portfolioDeleted) {
            log.info("Deleted portfolio for user {} during compensation", userId);
        } else {
            log.warn("Portfolio for user {} not found during compensation", userId);
        }

        userCompensationProducer.publishUserDeletion(
            userId,
            userName,
            email,
            "Portfolio compensation job %d requested user rollback".formatted(job.getKey())
        );

        Map<String, Object> updates = new HashMap<>();
        updates.put("isPortfolioCreated", portfolioDeleted ? Boolean.FALSE : Boolean.TRUE);
        client.newCompleteCommand(job.getKey())
            .variables(updates)
            .send()
            .join();
    }

    private boolean deletePortfolioWithWait(String userId) {
        if (portfolioService.getPortfolio(userId).isPresent()) {
            return portfolioService.deletePortfolioForUser(userId);
        }
        long deadline = System.currentTimeMillis() + CREATION_WAIT_TIMEOUT.toMillis();
        while (System.currentTimeMillis() < deadline) {
            if (portfolioService.getPortfolio(userId).isPresent()) {
                return portfolioService.deletePortfolioForUser(userId);
            }
            try {
                Thread.sleep(CREATION_POLL_INTERVAL.toMillis());
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("Compensation wait interrupted", ex);
            }
        }
        return portfolioService.getPortfolio(userId).isPresent()
            && portfolioService.deletePortfolioForUser(userId);
    }

    private String requireString(Map<String, Object> variables, String key) {
        Object value = variables.get(key);
        if (value == null) {
            throw new IllegalStateException(key + " variable missing for portfolio compensation job");
        }
        return value.toString();
    }

    private String asNullableString(Object value) {
        return value != null ? value.toString() : null;
    }
}
