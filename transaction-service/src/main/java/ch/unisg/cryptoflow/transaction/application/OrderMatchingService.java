package ch.unisg.cryptoflow.transaction.application;

import ch.unisg.cryptoflow.transaction.domain.PendingOrder;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.Collection;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Tracks pending orders and matches them against incoming price events.
 *
 * <p>When a price event arrives for a symbol with a price at or below the
 * target price of a pending order, that order is considered matched and
 * removed from the pending set.
 */
@Service
@Slf4j
public class OrderMatchingService {

    private final Map<String, PendingOrder> pendingOrders = new ConcurrentHashMap<>();

    public void registerOrder(PendingOrder order) {
        pendingOrders.put(order.transactionId(), order);
        log.info("Registered pending order: transactionId={} symbol={} targetPrice={}",
                order.transactionId(), order.symbol(), order.targetPrice());
    }

    /**
     * Evaluates all pending orders for the given symbol against the incoming price.
     *
     * @return all orders whose target price is met (price <= targetPrice)
     */
    public Collection<PendingOrder> matchOrders(String symbol, BigDecimal currentPrice) {
        return pendingOrders.values().stream()
                .filter(order -> order.symbol().equalsIgnoreCase(symbol))
                .filter(order -> currentPrice.compareTo(order.targetPrice()) <= 0)
                .toList();
    }

    public Optional<PendingOrder> removeOrder(String transactionId) {
        PendingOrder removed = pendingOrders.remove(transactionId);
        return Optional.ofNullable(removed);
    }
}