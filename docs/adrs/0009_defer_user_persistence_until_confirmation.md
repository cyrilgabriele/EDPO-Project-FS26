# 9. Defer user persistence until email confirmation

Date: 2026-03-15
Author: Cyril Gabriele

## Status

Accepted

## Context

`user-service` used to persist a user record as soon as the Camunda user task collected credentials, even though the address had never been verified. This polluted the `users` table with unconfirmed records, complicated GDPR cleanup, and made it impossible to revoke access before onboarding completed.

## Decision

Only create the `User` aggregate after the onboarding process receives a `UserConfirmed` message. The BPMN model now stages data via `userPreparationWorker`, waits on an intermediate message catch event keyed by the generated UUID, and calls `userCreationWorker` (which writes to Postgres) only after the magic-link was clicked.

## Consequences

- `UserCreationWorker` depends on the pre-generated `UserId` variable and no longer generates UUIDs itself.
- Pending requests simply time out if the recipient never confirms, keeping the database clean but requiring Operate/alerts for stale instances.
- Downstream services can trust that every persisted user owns the email used for login notifications.
