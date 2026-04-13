package ch.unisg.cryptoflow.transaction.adapter.in.web;

import ch.unisg.cryptoflow.transaction.adapter.out.persistence.ConfirmedUserRepository;
import ch.unisg.cryptoflow.transaction.adapter.out.persistence.SpringDataOutboxEventRepository;
import ch.unisg.cryptoflow.transaction.adapter.out.persistence.SpringDataTransactionRecordRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Exposes dashboard data for the static demo page at {@code /}.
 * Surfaces recent transactions, outbox state, and the confirmed-user read-model.
 */
@RestController
@RequestMapping("/api/dashboard")
@RequiredArgsConstructor
public class TransactionDashboardController {

    private final SpringDataTransactionRecordRepository transactionRepo;
    private final SpringDataOutboxEventRepository outboxRepo;
    private final ConfirmedUserRepository confirmedUserRepo;

    @GetMapping
    public Map<String, Object> dashboard() {
        var transactions = transactionRepo.findAll(
                PageRequest.of(0, 20, Sort.by(Sort.Direction.DESC, "placedAt"))
        ).stream().map(t -> Map.of(
                "transactionId", t.getTransactionId(),
                "userId",        t.getUserId(),
                "symbol",        t.getSymbol(),
                "amount",        t.getAmount().toPlainString(),
                "targetPrice",   t.getTargetPrice().toPlainString(),
                "status",        t.getStatus().name(),
                "placedAt",      t.getPlacedAt().toString(),
                "resolvedAt",    t.getResolvedAt() != null ? t.getResolvedAt().toString() : "",
                "matchedPrice",  t.getMatchedPrice() != null ? t.getMatchedPrice().toPlainString() : ""
        )).toList();

        var outbox = outboxRepo.findAll(
                PageRequest.of(0, 15, Sort.by(Sort.Direction.DESC, "createdAt"))
        ).stream().map(o -> Map.of(
                "eventId",       o.getEventId(),
                "transactionId", o.getTransactionId(),
                "topic",         o.getTopic(),
                "createdAt",     o.getCreatedAt().toString(),
                "publishedAt",   o.getPublishedAt() != null ? o.getPublishedAt().toString() : "",
                "published",     o.isPublished()
        )).toList();

        var confirmedUsers = confirmedUserRepo.findAll(
                Sort.by(Sort.Direction.DESC, "confirmedAt")
        ).stream().map(u -> Map.of(
                "userId",      u.getUserId(),
                "userName",    u.getUserName() != null ? u.getUserName() : "",
                "confirmedAt", u.getConfirmedAt().toString()
        )).toList();

        return Map.of(
                "service",        "transaction-service",
                "transactions",   transactions,
                "outbox",         outbox,
                "confirmedUsers", confirmedUsers
        );
    }
}
