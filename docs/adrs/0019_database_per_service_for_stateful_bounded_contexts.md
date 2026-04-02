# ADR-0019: Database per Service for Stateful Bounded Contexts

**Date**: 2026-04-02

## Status

Accepted

## Context

CryptoFlow now contains multiple stateful bounded contexts: user identity, portfolio management,
and trading. These services collaborate through Kafka and Camunda-based sagas, but evolve on
different cadences and own different invariants.

A shared database would couple schema changes, deployment timing, transaction boundaries, and
operational ownership across services. It would also collapse several independently deployable
architecture quanta into one deployable unit.

## Decision

Use a database-per-service model for every stateful bounded context.

- `user-service` owns `user_service_db`
- `portfolio-service` owns `portfolio_service_db`
- `transaction-service` owns `transaction_service_db`

No service may read from or write to another service's tables. Cross-service references use opaque
identifiers and replicated read models, not foreign keys or joins. Each service manages its schema
through Flyway migrations and runs Hibernate in validate-only mode.

This keeps each stateful service as an independently deployable architecture quantum. Cross-service
consistency is achieved through Kafka events, replicated read models, outbox publication, and
orchestrated sagas rather than shared SQL transactions.

ADR-0007 remains the portfolio-specific application of this system-wide rule.

## Consequences

**Positive**
- Reduced structural coupling between services and schemas.
- More independently deployable architecture quanta: each service can evolve, migrate, and deploy
  without coordinating database changes with another service.
- Failure isolation: schema mistakes or heavy queries in one service do not directly corrupt
  another bounded context.
- Persistence ownership stays aligned with bounded-context ownership.

**Negative**
- No cross-service ACID transactions or joins.
- Cross-service workflows become eventually consistent.
- Additional integration patterns are required: sagas, compensation, outbox, idempotent consumers,
  and replicated read models.

This trade-off is already accepted elsewhere in the architecture:

- ADR-0001 chooses asynchronous inter-service communication over synchronous coordination.
- ADR-0010 and ADR-0011 accept saga orchestration and compensation instead of shared transactions.
- ADR-0013 and ADR-0015 accept eventual consistency for order approval and portfolio propagation.
- ADR-0017 accepts replicated read models over synchronous validation calls.

## References

- ADR-0001 · ADR-0007 · ADR-0010 · ADR-0011 · ADR-0013 · ADR-0015 · ADR-0017
