package ch.unisg.cryptoflow.transaction.adapter.out.camunda;

import io.camunda.zeebe.client.ZeebeClient;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.Duration;
import java.util.Map;

/**
 * Outgoing adapter that publishes messages to Camunda 8 to continue
 * waiting workflow instances.
 *
 * <p>Uses the {@code transactionId} as correlation key so the correct
 * process instance receives the message.
 */
@Component
@Slf4j
@RequiredArgsConstructor
public class OrderExecutedMessageSender {

    private final ZeebeClient zeebeClient;

    /**
     * Sends a "price-matched" message to the workflow instance identified
     * by the given transactionId.
     */
    public void sendPriceMatchedMessage(String transactionId, String symbol, BigDecimal matchedPrice) {
        log.info("Sending price-matched message: transactionId={} symbol={} matchedPrice={}",
                transactionId, symbol, matchedPrice);

        zeebeClient.newPublishMessageCommand()
                .messageName("price-matched")
                .correlationKey(transactionId)
                .variables(Map.of(
                        "matchedPrice", matchedPrice.toPlainString(),
                        "matchedSymbol", symbol,
                        "priceMatched", true
                ))
                .timeToLive(Duration.ofMinutes(5))
                .send()
                .exceptionally(ex -> {
                    log.error("Failed to send price-matched message for transactionId={}: {}",
                            transactionId, ex.getMessage());
                    return null;
                });
    }
}
