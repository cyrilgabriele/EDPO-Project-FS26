package ch.unisg.cryptoflow.transaction.domain;

import java.math.BigDecimal;
import java.time.Instant;

public record PendingOrder(
        String transactionId,
        String symbol,
        BigDecimal amount,
        BigDecimal targetPrice,
        Instant createdAt
) {}