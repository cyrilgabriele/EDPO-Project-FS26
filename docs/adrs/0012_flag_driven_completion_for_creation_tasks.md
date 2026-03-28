# 12. Flag-driven completion for creation tasks

Date: 2026-03-28

## Status

Accepted

## Context

The onboarding BPMN process fans out to the `userCreationWorker` and `portfolioCreationWorker` service
tasks and then joins again only if both `isUserCreated`/`isPortfolioCreated` flags are true
(`onboarding-service/src/main/resources/userOnboarding.bpmn:121`). The two workers already translate
all local outcomes – duplicates, validation errors, or deliberate compensation triggers – into those
flags before completing their jobs (`user-service/.../UserCreationWorker.java:25`,
`portfolio-service/.../PortfolioCreationWorker.java:24`). Throwing Camunda errors would short-circuit
the flow, bypassing the gateways and compensation events we modelled in ADR-0011.

## Decision

Complete both workers successfully and communicate the outcome exclusively through the boolean
variables that the BPMN gateways inspect; do not rely on Zeebe error handling for these tasks.

- `UserCreationWorker` catches expected `IllegalStateException`s or compensation triggers and always
  completes the job with `isUserCreated=false` when persistence fails
  (`user-service/.../UserCreationWorker.java:34-62`).
- `PortfolioCreationWorker` mirrors this pattern, populating `isPortfolioCreated`/`portfolioId` even
  when `PortfolioService` refuses to persist because an entry already exists or inputs are invalid
  (`portfolio-service/.../PortfolioCreationWorker.java:32-65`).
- The BPMN gateways continue to read those variables; a `false` route throws a compensation event so
  the orchestrator can invoke the compensation workers without Zeebe incidents
  (`onboarding-service/src/main/resources/userOnboarding.bpmn:127-164`).

## Consequences

- **Deterministic unhappy paths:** Duplicate user IDs, connectivity blips, or rare validation issues
  are modelled identically – they flip the flag to `false`, ensuring the compensation steps always
  run and the saga instance terminates cleanly.
- **No Zeebe incidents to unblock manually:** Operators see errors in service logs and compensation
  events instead of stuck jobs, which keeps the orchestrator queue flowing even during retries.
- **Requires careful logging/metrics:** Because incidents are suppressed, we must rely on
  observability in the user and portfolio services to detect systemic failures and avoid silently
  losing creation capability.
