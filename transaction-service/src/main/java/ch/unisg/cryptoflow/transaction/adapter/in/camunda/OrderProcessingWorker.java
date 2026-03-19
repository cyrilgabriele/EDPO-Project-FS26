package ch.unisg.cryptoflow.transaction.adapter.in.camunda;

import ch.unisg.cryptoflow.transaction.adapter.in.camunda.job.OrderProcessingVariables;
import ch.unisg.cryptoflow.transaction.application.OrderMatchingService;
import ch.unisg.cryptoflow.transaction.domain.PendingOrder;
import io.camunda.zeebe.client.api.response.ActivatedJob;
import io.camunda.zeebe.client.api.worker.JobClient;
import io.camunda.zeebe.spring.client.annotation.JobWorker;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * Incoming Camunda adapter – handles the "retrieve-order" job from the BPMN workflow.
 *
 * <p>Generates a transactionId, registers the order as pending so the
 * price-matching Kafka consumer can correlate incoming price events.
 */
@Component
@Slf4j
@RequiredArgsConstructor
public class OrderProcessingWorker {

    private final OrderMatchingService orderMatchingService;

    /**
     * Executes the "order-processing-worker" job by retrieving order details, generating a unique
     * transaction ID, registering the order as pending with the order matching service, and returning
     * updated job variables.
     *
     * @param jobClient the client used to interact with the job worker system
     * @param job the activated job containing job variables and contextual information
     * @return a map of job variables, including the generated transactionId
     */
    @JobWorker(type = "order-processing-worker", autoComplete = true)
    public Map<String, Object> orderProcessingWorker(JobClient jobClient, ActivatedJob job) {
        log.debug("Retrieving order");
        Map<String, Object> jobVariables = job.getVariablesAsMap();
        OrderProcessingVariables variables = OrderProcessingVariables.fromMap(jobVariables);
        String transactionId = UUID.randomUUID().toString();
        log.debug("{} | transactionId: {}", variables, transactionId);

        PendingOrder pendingOrder = new PendingOrder(
                transactionId,
                variables.symbol(),
                new BigDecimal(variables.amount()),
                new BigDecimal(variables.price()),
                Instant.now()
        );
        orderMatchingService.registerOrder(pendingOrder);

        jobVariables.put("transactionId", transactionId);
        return jobVariables;
    }
}
