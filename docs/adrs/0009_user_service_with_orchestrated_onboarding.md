# 9. Introduce a dedicated user-service with Camunda-orchestrated onboarding

Date: 2026-03-15

## Status

Accepted

## Context

Portfolio and transaction services operate on behalf of identifiable users. No service currently
owns the User aggregate or provides a verified identity as a first-class domain concept.

User registration is a multi-step stateful workflow: credential collection, email dispatch, and
account activation triggered by an external browser request. The unbounded wait between dispatch
and activation, combined with the need for timeout and compensation handling, makes this a
direct fit for Camunda 8 process orchestration (ADR-0008) rather than imperative application code.

## Decision

Introduce `user-service` as the authoritative owner of the User aggregate. Registration is
implemented as a Camunda 8 BPMN process that collects credentials via a user form task,
sends a confirmation email via the Camunda email connector, and suspends at an intermediate
message catch event keyed by a pre-generated UUID. The User aggregate is written to PostgreSQL
only after the `UserConfirmedEvent` message is correlated — there is no intermediate persisted state.

## Consequences

- **Authoritative identity source:** User management logic is owned exclusively by `user-service`;
  portfolio and transaction services reference its aggregates without duplicating identity concerns.
- **Verified identity invariant:** Every record in the `users` table has a confirmed email
  address. No downstream status check is required.
- **Process state in Zeebe:** Pending registrations live as Zeebe process instances, not database
  rows. Timeout and incident handling is managed via Camunda Operate, not application code.
- **Public endpoint required:** `USER_CONFIRMATION_BASE_URL` must be set to an externally
  accessible address in every deployment environment.
- **Additional operational surface:** `user-service` introduces its own database schema,
  worker process, and deployment lifecycle.
