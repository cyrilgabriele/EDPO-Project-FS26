# ADR-0013: Fairy Tale Saga (seo) for the placeOrder Workflow

**Date**: 2026-03-30

## Status

Accepted

## Context

The `placeOrder` workflow contains an Event-Based Gateway that waits for an external price-match signal of **non-deterministic duration**. This means that the wait may last seconds or never terminate. Each service task owns its own local ACID transaction. Cross-service state (portfolio holdings) must eventually be consistent with the transaction record.

The saga pattern choice determines how failures are handled and how tightly `transaction-service` and `portfolio-service` are coupled.

## Decision

Adopt the **Fairy Tale Saga (seo)**: synchronous service tasks + eventual cross-service consistency + Zeebe as orchestrator.

Each worker completes a local ACID transaction and returns synchronously to Zeebe. Cross-service consistency with `portfolio-service` is eventual, carried over Kafka (ADR-0001). Zeebe durably suspends the process at the Event-Based Gateway without holding any distributed lock or DB connection.

Deterministic, non-retryable failures (invalid input, missing records) are handled via BPMN error boundaries rather than saga compensation — see ADR-0018.

## Consequences

**Positive**
- Zeebe persists process state across the unbounded gateway wait with no resource held open.
- Each service retains full control of its own schema and transaction boundary (ADR-0007).
- Infrastructure failures are handled by Zeebe's built-in retry and incident mechanism — no custom logic required.

**Negative**
- Eventual inconsistency window exists between APPROVED status and the portfolio update. Mitigated by ADR-0014 (outbox) and ADR-0015 (durability).
- An APPROVED order is semantically terminal — no saga-level compensation is modelled.

## Alternatives Considered

**Epic Saga (sao) — Synchronous + Atomic + Orchestrated**
Requires a distributed transaction spanning the Event-Based Gateway. With a non-deterministic wait, this blocks DB connections indefinitely and makes coordination across PostgreSQL and Kafka structurally impossible. Rejected.

**Parallel Saga (aeo) — Asynchronous + Eventual + Orchestrated**
Replaces synchronous workers with async send tasks + message catch events throughout. Stronger durability at the cost of significantly higher BPMN and operational complexity for steps that have no blocking concern. Partially adopted for the post-approval leg (ADR-0015).

## References

- ADR-0001 · ADR-0007 · ADR-0008 · ADR-0014 · ADR-0015 · ADR-0018
- *Software Architecture: The Hard Parts*, Ch. 12 — Fairy Tale Saga (Table 12-4)
