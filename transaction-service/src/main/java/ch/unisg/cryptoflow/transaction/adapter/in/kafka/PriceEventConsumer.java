package ch.unisg.cryptoflow.transaction.adapter.in.kafka;

import ch.unisg.cryptoflow.events.CryptoPriceUpdatedEvent;
import ch.unisg.cryptoflow.transaction.adapter.out.camunda.OrderExecutedMessageSender;
import ch.unisg.cryptoflow.transaction.application.OrderMatchingService;
import ch.unisg.cryptoflow.transaction.domain.PendingOrder;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import java.util.Collection;

/**
 * Kafka consumer adapter for {@code crypto.price.raw}.
 *
 * <p>Consumes price events and checks them against all pending orders.
 * When a price matches (current price &le; target price for the same symbol),
 * it sends a "price-matched" message to the Camunda workflow via the
 * {@link OrderExecutedMessageSender}, using the transactionId as correlation key.
 */
@Component
@Slf4j
@RequiredArgsConstructor
public class PriceEventConsumer {

    private final OrderMatchingService orderMatchingService;
    private final OrderExecutedMessageSender orderExecutedMessageSender;

    @KafkaListener(
            topics = "${crypto.kafka.topic.price-raw}",
            groupId = "${spring.kafka.consumer.group-id}",
            containerFactory = "kafkaListenerContainerFactory"
    )
    public void onPriceUpdated(CryptoPriceUpdatedEvent event) {
        if (event == null || event.symbol() == null || event.price() == null) {
            log.warn("Received null or malformed price event – skipping");
            return;
        }

        log.debug("Consumed price event: symbol={} price={}", event.symbol(), event.price());

        Collection<PendingOrder> matched = orderMatchingService.matchOrders(
                event.symbol(), event.price());

        for (PendingOrder order : matched) {
            log.info("Price matched for order: transactionId={} symbol={} targetPrice={} currentPrice={}",
                    order.transactionId(), order.symbol(), order.targetPrice(), event.price());

            orderMatchingService.removeOrder(order.transactionId());

            orderExecutedMessageSender.sendPriceMatchedMessage(
                    order.transactionId(),
                    event.symbol(),
                    event.price()
            );
        }
    }
}
