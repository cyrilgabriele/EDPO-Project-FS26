# 10. Dedicated onboarding-service as saga orchestrator

Date: 2026-03-23

## Status

Accepted

## Context

ADR-0009 introduced a Camunda-orchestrated onboarding flow within `user-service`. Since then,
the registration scope expanded: after a user confirms the link, we must create both the user
aggregate and a tailor-made portfolio. This requires a Parallel Saga (Lecture 5, slides 77-81)
coordinating multiple local transactions in different bounded contexts (user and portfolio services).

Keeping the BPMN inside `user-service` creates several issues:

- The orchestrator now coordinates work owned by two separate services, increasing coupling.
- user-service exposes UI forms and confirmation endpoints; tying workflow deployment to it
  complicates releases and violates hexagonal boundaries.
- Additional saga branches (e.g., Know YOur Customer (KYC), initial funding) are easier to grow in a dedicated context.

## Decision

Introduce `onboarding-service` as a dedicated orchestration service. It owns the BPMN process
(`userOnboarding.bpmn`) and deploys it via the Camunda 8 Zeebe client. The user-facing form still
triggers the process through Camunda Tasklist, but the BPMN now coordinates four workers:
`prepareUserWorker` (user-service) runs before the confirmation wait, generating the `userId`,
building the confirmation URL, and persisting a `user_confirmation_links` row as `PENDING` so that
user-service keeps definitive saga state. Once the `UserConfirmed` message arrives, a Parallel
Gateway fans out to `userCreationWorker` (user-service) and `portfolioCreationWorker`
(portfolio-service) whose jobs must both succeed before the saga proceeds. A boundary timer leads to
`invalidateConfirmationWorker` (user-service) that marks any stale confirmation rows `INVALIDATED`
automatically.

Each domain service continues to host its Zeebe workers and local persistence; additionally,
user-service actively publishes the `UserConfirmed` correlation message from its
`UserConfirmationController`, so it plays both worker-host and message-sender roles while
onboarding-service remains the only BPMN orchestrator.

## Consequences

- **Clear ownership:** onboarding-service focuses on orchestration; user and portfolio services
  keep their domain responsibilities without embedding BPMN deployments.
- **Parallel Saga compliance:** the BPMN explicitly models the pattern shown in class: a single
  orchestrator coordinating eventual consistency across services.
- **Scalability for future steps:** additional branches (e.g., risk checks) can be added to the BPMN
  without touching the domain services.
- **Operational overhead:** onboarding-service is a new deployable unit with its own Camunda
  credentials and monitoring. Downtime affects only workflow initiation, not user/portfolio APIs.
- **Latency:** orchestrator introduces hop-by-hop communication but still avoids tight coupling
  thanks to Zeebe’s job worker model.
