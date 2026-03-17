# 1. Use Apache Kafka as the inter-service event bus

Date: 2026-03-01

## Status

Partially superseded by [ADR-0008](0008_camunda_8_for_process_orchestration.md) — Kafka remains
the inter-service event bus for domain events; ADR-0008 introduces Zeebe as a complementary
coordination channel for orchestrated process workflows.

## Context

CryptoFlow consists of multiple microservices (market-data-service, portfolio-service,
transaction-service, user-service). Services need to exchange domain events (price updates,
order state changes) without direct coupling. Options considered: synchronous REST calls
between services, a message broker (RabbitMQ, Kafka), or a hybrid approach.

REST introduces tight runtime coupling — the caller blocks until the callee responds, and
both must be online simultaneously. RabbitMQ is a viable message broker but lacks Kafka's
durable, replayable log and native partitioning model. Kafka provides persistent ordered
streams, consumer groups, and configurable retention — well suited for event-driven
architectures where consumers may join or restart independently.

## Decision

All inter-service domain events flow through Apache Kafka. Services do not call each other
via REST. Each service exposes REST endpoints exclusively for external clients.

### Broker configuration

- **KRaft mode** (no Zookeeper). The Kafka broker runs with `KAFKA_PROCESS_ROLES=broker,controller`
  in a single-node setup, eliminating the Zookeeper dependency.
- **Auto topic creation disabled** (`auto.create.topics.enable=false`). Topics are declared
  programmatically in `KafkaTopicConfig` via Spring `NewTopic` beans. This prevents typos
  or misconfigured producers from silently creating unintended topics.
- **Log retention:** 1 hour, 100 MB per partition. Sufficient for real-time price streaming;
  consumers that fall behind beyond this window lose events. Portfolio state is persisted
  separately (ADR-0007), so Kafka is not the system of record.

### Topic topology

| Topic | Partitions | Replicas | Purpose |
|-------|-----------|----------|---------|
| `crypto.price.raw` | 3 | 1 | Price events from market-data-service |
| `crypto.price.raw.DLT` | 1 | 1 | Dead letters for failed price event processing |

### Consumer resilience

Each consuming service (portfolio-service, transaction-service) configures:

- **Auto-commit disabled.** Offsets are committed after processing, not on poll.
- **Error-handling deserializer.** `ErrorHandlingDeserializer` wraps `JsonDeserializer`.
  Poison pills (malformed messages) are caught at deserialization rather than crashing the
  consumer loop.
- **Dead Letter Topic (DLT) recovery.** After 3 attempts (2 retries at 500ms fixed backoff),
  a failed record is published to `crypto.price.raw.DLT` and the consumer advances. This
  prevents a single bad record from blocking the partition.
- **Auto offset reset: `earliest`.** New consumer groups start from the beginning of retained
  history, ensuring no events are missed on first deployment.

### Producer configuration

- **Acknowledgement mode.** `acks=all` — the broker acknowledges only after all in-sync replicas confirm the write.
  With a single replica this is functionally equivalent to `acks=1`, but the setting is
  forward-compatible with a multi-broker deployment.
- **JSON serialization** with Spring `JsonSerializer`, type headers disabled (see ADR-0003).

## Consequences

- **Loose coupling:** Services have no compile-time or runtime dependency on each other.
  Adding a new consumer requires zero changes to the producer.
- **Temporal decoupling:** Services do not need to be online simultaneously. Kafka retains
  messages within the retention window, so a restarting consumer picks up where it left off.
- **Auditability:** Kafka's durable log provides a natural audit trail of all inter-service
  events. Kafka UI exposes topic contents for debugging.
- **Poison pill isolation:** The DLT pattern ensures one malformed event does not stall
  an entire consumer group. Failed records are preserved in the DLT for inspection without
  manual intervention.
- **Short retention window:** The 1-hour retention means Kafka cannot serve as a long-term
  event store. Any service that requires historical data must persist it independently.
- **Eventual consistency:** Consumers see events with a slight delay. Acceptable for price
  ticks, but workflows that require transactional coordination use Zeebe (ADR-0008) rather
  than Kafka request-reply patterns.
- **Single-broker limitation:** The current single-node KRaft setup has no replication or
  failover. Acceptable for development and a university project; a production deployment
  would require a multi-broker cluster.
