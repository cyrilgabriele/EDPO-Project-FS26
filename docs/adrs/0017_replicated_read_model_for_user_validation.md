# ADR-0017: Replicated Read-Model for User Validation at Order Placement

**Date**: 2026-03-31

## Status

Accepted

## Context

`transaction-service` must reject orders from users who have not completed registration. The straightforward solution — a synchronous HTTP call to `user-service` at order placement — introduces runtime coupling: if `user-service` is slow or unavailable, all order placement is blocked. This violates the service autonomy principle established in ADR-0001 and ADR-0007.

## Decision

`transaction-service` maintains a local **replicated read-model** of confirmed users in its own database. The table is kept current via **Event-Carried State Transfer** (ADR-0002):

1. When a user completes email confirmation, `user-service` publishes a `UserConfirmedEvent` to a **log-compacted** Kafka topic (`user.confirmed`, keyed by `userId`).
2. `transaction-service` consumes the event and upserts into its local confirmed-users table.
3. Order validation is a local database read — no network call.

Log compaction ensures the read-model can be fully reconstructed from the topic on cold start or after a crash, regardless of how long the service was offline.

## Consequences

**Positive**
- `transaction-service` validates orders autonomously, even when `user-service` is unavailable.
- Validation is a sub-millisecond in-process DB read.
- Re-delivery of `UserConfirmedEvent` is handled gracefully — upsert by primary key is idempotent.

**Negative**
- Brief eventual consistency window: a user confirmed milliseconds ago may not yet appear in the read-model if consumer lag is non-zero. Acceptable — a newly confirmed user is not expected to place an order immediately.
- If user accounts can be deactivated, a compensating `UserDeactivatedEvent` is required to remove the row. Not yet implemented and declared as out of scope.

## Alternatives Considered

**Synchronous HTTP call to `user-service`**
Simple, always consistent. Rejected: introduces availability coupling — a slow or down `user-service` blocks all order placement. Violates ADR-0001 (Kafka as sole inter-service communication).

**Check portfolio existence as proxy for user confirmation**
Call `portfolio-service` instead. Rejected: semantically incorrect and fragile — portfolio creation is a consequence of user confirmation, not equivalent to it.

## References

- ADR-0001 · ADR-0002 · ADR-0007
