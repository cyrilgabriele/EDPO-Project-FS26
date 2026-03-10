# 1. Use Apache Kafka as the sole inter-service communication mechanism

Date: 2026-03-01

## Status

Accepted

## Context

CryptoFlow consists of multiple microservices (market-data-service, portfolio-service, and future services). We need to decide how these services communicate. Options include synchronous REST calls between services, a message broker (RabbitMQ, Kafka), or a hybrid approach.

## Decision

All inter-service communication goes through Apache Kafka. Services do not call each other via REST. Each service only exposes REST endpoints for external clients, never for other services.

## Consequences

- **Loose coupling:** Services have no compile-time or runtime dependency on each other. Adding a new consumer requires zero changes to the producer.
- **Temporal decoupling:** Services do not need to be online simultaneously. Kafka retains messages, so a consumer that restarts picks up where it left off.
- **Auditability:** Kafka's durable log provides a natural audit trail of all inter-service events.
- **Increased complexity:** Debugging message flows is harder than tracing synchronous REST calls. Requires Kafka infrastructure (broker, monitoring).
- **Eventual consistency:** Consumers see data with a slight delay. This is acceptable for price ticks but may require careful handling for future transactional flows.
- **No request-reply:** Pure event-driven communication makes synchronous query patterns across services impossible; each service must maintain its own state.
