= Experiments: Results & Insights <results>

This chapter presents the experimental results obtained during the project, covering the Kafka reliability experiments from Exercise 1 and the implementation findings they informed. The chapter summarizes the key outcomes; the full consolidated experiment notes, command transcripts, screenshots, and reproduction steps are documented in `assignments/ex-1/experiments.md`.

== Kafka Producer Reliability: Message Loss with acks=0

*Objective:* Demonstrate that disabling acknowledgments and retries results in permanent data loss when the Kafka leader broker crashes.

*Setup:* A two-broker Kafka cluster (KRaft mode) with a `ClickStream-Producer` configured with `acks=0` and `retries=0`, emitting one event approximately every 150 ms. A `ClickStream-Consumer` logs received events.

*Procedure:* While the producer and consumer were running, the active leader was identified via `kafka-topics --describe` and then hard-killed using `docker stop`.

*Result:* The producer logged `eventID=75`, `eventID=76`, and `eventID=77` as sent, but the consumer log jumps directly from `eventID=75` to `eventID=77`. `eventID=76` was permanently lost, and the producer received no error because `acks=0` means fire-and-forget.

*Insight:* With `acks=0`, the application has no mechanism to detect or recover from message loss: Kafka may never durably receive the record, and the producer cannot tell. The experiment showed that durability requires at least `acks=all` and `retries > 0`; to avoid duplicates during retry, `enable.idempotence=true` should also be enabled. This directly supports the durable-write choice documented in @adr-0001.

== Consumer Offset Behavior

=== Safe Replay with auto.offset.reset=earliest

*Objective:* Confirm that when no committed offsets exist, `earliest` forces a full replay of retained events.

*Setup:* A fresh consumer group (`grp1`) with `auto.offset.reset=earliest`. Events were produced before the consumer started.

*Result:* The consumer received all events from offset 0, including those produced before it joined. After being killed before auto-commit and restarted, it logged a reset back to `offset=0` and replayed the retained backlog from the beginning again.

*Insight:* If no committed offsets exist, `earliest` replays the oldest records Kafka still retains, so replay is deterministic for the retained backlog. This is useful for at-least-once processing and short-term recovery, but it does not preserve the topic's full history forever: once the retention policy deletes older records, they cannot be replayed. The operational cost is that restarts may require processing the full retained backlog again.

=== Data Gap with auto.offset.reset=latest

*Objective:* Show that `latest` causes new consumer groups to miss all previously retained events.

*Setup:* A fresh consumer group (`grp2`) with `auto.offset.reset=latest`. Retained events existed on the topic.

*Result:* The new consumer group reset directly to the tail of the topic (`offset=90` in the observed run), skipped the retained history, and only began receiving newly produced messages afterward. From the application's perspective, the historical data was effectively lost.

*Insight:* `latest` is unsafe for workloads that require replay of retained data. Explicit use of `earliest`, manual `seek`, or pre-seeded offsets is necessary to prevent silent data gaps.

For further details on the producer and consumer experiments, including screenshots and the exact run procedures, see `assignments/ex-1/experiments.md`.

== Fault Tolerance: Leader Failover Timing

*Objective:* Measure the availability gap during a leader broker crash and verify that no acknowledged data is lost.

*Setup:* A three-broker Kafka cluster with `acks=all`. The active leader was hard-killed during active production.

*Result:* The last acknowledged event before the crash was `id=212` at `18:12:51.570`. The leader changed from broker `2` to broker `3`, detected at `18:13:00.375`. The measured timings were `lastAckToLeaderElectedMs=8805`, `lastAckToFirstRecoveredAckMs=8890`, and `firstAckAfterRecoveryMs=85`. The first event acknowledged after recovery was `id=213`, and the consumer processed events `211..271` with no gaps.

*Insight:* With `acks=all`, leader failover was an availability event, not a durability event. No acknowledged data was lost. The more useful outage measurement is from the last successful ACK to the first recovered ACK, not from the leader-election log line, because most of the pause elapsed before the election was reported.

== Fault Tolerance: Data Loss with acks=1

*Objective:* Demonstrate that leader-only acknowledgment (`acks=1`) can lose records when the leader crashes before replication completes.

*Setup:* The same three-broker cluster, but with `acks=1` and `retries=0`. Replication lag was artificially increased via `replica.fetch.wait.max.ms=3000` to widen the loss window.

*Result:* Around the crash, the producer logged `ACKED id=70`, `ACKED id=71`, then queued `id=72` and `id=73`. After recovery, the consumer logged `eventID=70`, then `GAP DETECTED from=71 to=71`, and then continued with `eventID=72` and `eventID=73`. `eventID=71` had been acknowledged by the leader but never reached the followers before the crash, so it was permanently lost.

*Insight:* `acks=1` only guarantees that the leader appended the record; it says nothing about replication to followers. In this setup, `replica.fetch.wait.max.ms=3000` deliberately widened the loss window enough to trigger manually. For durable writes, the safe baseline is `acks=all`, plus retries and producer idempotence.

For the complete fault-tolerance experiment logs, timings, and configuration notes, see `assignments/ex-1/experiments.md`.

== Implementation Observations

=== Event-Carried State Transfer Performance

The `LocalPriceCache` in the portfolio service, implemented as a `ConcurrentHashMap`, handles the six-symbol price feed without contention issues. With Binance pushing updates at variable rates (sub-second during active markets), the cache stays current within milliseconds under normal conditions. The 503 warm-up behavior — returning an error until the first price event arrives — was validated as an effective guard against serving stale-from-startup values.

=== Portfolio Update Idempotency After Consumer Failure

During integration work, we accidentally reproduced the failure mode later documented in @adr-0016. Taking `portfolio-service` offline after processing an `OrderApprovedEvent` but before the Kafka offset was safely committed caused the same event to be delivered again on restart. Without a deduplication guard, a `2 BTC` order was applied twice and the portfolio incorrectly showed `4 BTC`.

The fix is the idempotent-consumer design from @adr-0016: before applying the holding update, `portfolio-service` inserts the event's `transactionId` into `processed_transaction` under a `UNIQUE` constraint inside the same transaction as `upsertHolding()`. If the insert fails, the event is a replay and is skipped; if it succeeds, both the deduplication marker and the holding update commit atomically. This turned an accidental failure into concrete validation of the need for consumer-side idempotency under at-least-once delivery.

=== Saga Compensation Reliability

The onboarding saga's compensation flow was tested by deliberately triggering failures in the user and portfolio creation workers. The flag-driven completion pattern (ADR-0012) proved effective: the BPMN process consistently reached the correct compensation branch regardless of which creation step failed. The dual Kafka listener pattern (both services listening for both compensation topics) provides an additional safety net, though no cases were observed where the primary compensation path failed.

// TODO: Run formal load tests and document throughput numbers
// TODO: Measure end-to-end latency from Binance event to portfolio valuation
// TODO: Test concurrent onboarding saga instances to validate Zeebe scaling
