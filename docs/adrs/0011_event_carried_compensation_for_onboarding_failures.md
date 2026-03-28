# 11. Event-carried compensation for onboarding failures

Date: 2026-03-28

## Status

Accepted

## Context

ADR-0010 introduced onboarding-service as the parallel saga orchestrator that drives user creation
(user-service) and portfolio creation (portfolio-service) in lockstep. Either local transaction can
fail after its sibling succeeded, leaving orphaned entities that violate our invariant of "one user <->
one portfolio". The services live in different bounded contexts and expose only asynchronous
workers; adding synchronous rollback calls would couple them tightly and reintroduce availability
risks. We therefore need cross-service compensation that keeps ownership boundaries intact while
matching the course requirement for Event-Carried State Transfer (Lecture 2).

## Decision

Use Event-Carried State Transfer plus at-least-once messaging to delegate compensations across
services.

- user-service hosts `userCompensationWorker` (`user-service/.../UserCompensationWorker.java`) that
  deletes the local user aggregate and publishes a `PortfolioCompensationRequestedEvent` via Kafka
  (`PortfolioCompensationProducer`).
- portfolio-service hosts `portfolioCompensationWorker` (`portfolio-service/.../PortfolioCompensationWorker.java`)
  that deletes the local portfolio and publishes a `UserCompensationRequestedEvent` via Kafka
  (`UserCompensationProducer`).
- Both services also listen to the opposite topic (`crypto.user.compensation`,
  `crypto.portfolio.compensation`) with dedicated `@KafkaListener`s so that, even if Camunda or the
  orchestrator crashes, the remote service eventually receives a deletion request that carries all
  necessary state (userId UUID, userName/email, optional portfolioId) to execute compensation.
- Producers call `kafkaTemplate.send(...).get()` and listeners disable auto-commit, relying on
  Kafka's retries to achieve at-least-once delivery; deletions are idempotent and keyed by the
  shared user_id (UUID minted during `prepareUserWorker`).

## Consequences

- **Loose coupling:** Compensation logic stays inside each domain service; asynchronous events mean no
  direct HTTP dependency during rollback.
- **Resilient cross-deletes:** Even if the saga instance dies mid-way, the ECST events persist on
  Kafka, allowing the peer service to observe and complete its deletion later.
- **Idempotent semantics:** Duplicated events are harmless because operations are keyed by the unique
  `userId`; consumers first check for entity existence before deleting.
- **Operational overhead:** Two new Kafka topics, producers, and consumers must be deployed and
  monitored; failures now surface via topic lag instead of synchronous errors.
