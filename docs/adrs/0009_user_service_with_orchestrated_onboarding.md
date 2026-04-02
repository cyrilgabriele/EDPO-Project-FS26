# 9. Introduce a dedicated user-service as owner of user identity and confirmation state

Date: 2026-03-15

## Status

Accepted. Amended by [ADR-0010](0010_dedicated_onboarding_service_for_parallel_saga.md)

## Context

Portfolio and transaction services operate on behalf of identifiable users. No service currently
owns the User aggregate or the confirmation lifecycle as a first-class domain concept.

Registration is a multi-step workflow with an unbounded wait between email dispatch and browser
confirmation. After [ADR-0010](0010_dedicated_onboarding_service_for_parallel_saga.md), the BPMN
orchestration itself lives in `onboarding-service`, but the user-related state, confirmation
semantics, and user lifecycle still belong in `user-service`.

## Decision

Introduce `user-service` as the authoritative owner of the User aggregate and the confirmation
lifecycle.

- `onboarding-service` owns and deploys the onboarding BPMN process (ADR-0010); `user-service`
  participates via Zeebe workers and the public confirmation endpoint.
- `prepareUserWorker` generates the `userId`, builds the confirmation link, and persists a
  `user_confirmation_links` row as `PENDING` before the confirmation email is sent.
- `GET /user/confirm/{userId}` is handled by `user-service`. On successful confirmation it marks
  the link `CONFIRMED`, correlates `UserConfirmedEvent` back to Camunda, and publishes
  `user.confirmed` to Kafka.
- The `cryptoflow_user` row is persisted only after confirmation, via `userCreationWorker`.
  Pending confirmation state is stored in `user-service`; the User aggregate itself is not created
  before confirmation.

## Consequences

- **Authoritative identity boundary:** `user-service` owns user records, confirmation links,
  and user lifecycle rules.
- **Verified-user invariant:** Every persisted user has completed email confirmation;
  unconfirmed registrations exist only as confirmation-link state plus orchestration state.
- **Clear split of concerns:** `onboarding-service` owns workflow orchestration, while
  `user-service` owns domain data and user-facing confirmation semantics.
- **Public endpoint required:** `USER_CONFIRMATION_BASE_URL` must be set to an externally
  accessible address in every deployment environment.
- **Additional persistence:** Pending registrations are now visible in `user-service` through
  `user_confirmation_links`; they no longer live exclusively inside Zeebe.
- **Additional operational surface:** `user-service` introduces its own database schema,
  workers, and deployment lifecycle.
