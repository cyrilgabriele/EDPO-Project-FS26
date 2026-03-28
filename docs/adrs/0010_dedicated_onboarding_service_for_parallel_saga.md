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
- Additional saga branches (e.g., KYC, initial funding) are easier to grow in a dedicated context.

## Decision

Introduce `onboarding-service` as a dedicated orchestration service. It owns the BPMN process
(`userOnboarding.bpmn`) and deploys it via the Camunda 8 Zeebe client. The user-facing form
still triggers the process through Camunda Tasklist, but once mail confirmation arrives the process
fans out via a Parallel Gateway to two service tasks: `userCreationWorker` (served by user-service)
and `portfolioCreationWorker` (served by portfolio-service). The process joins after both jobs
finish, fulfilling the Parallel Saga pattern highlighted in Lecture 5.

Each domain service now only hosts its Zeebe workers and local persistence. The orchestrator
simply publishes jobs and listens for `UserConfirmedEvent` messages.

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
