# 11. Confirm user via HTTP endpoint and Zeebe message

Date: 2026-03-15
Author: Cyril Gabriele

## Status

Accepted

## Context

The confirmation link embedded in the email must be reachable from a browser. We considered having that link hit a lightweight page that writes to Kafka, but all the BPMN instance needs is a Zeebe message with the UUID; adding Kafka or polling would introduce unnecessary moving parts.

## Decision

Expose `GET /user/confirm/{userId}` in `user-service`. When invoked, it publishes the `UserConfirmed` Zeebe message using the UUID as the correlation key and reuses the same service to show a success/error response to the user.

## Consequences

- No extra infrastructure: the HTTP endpoint talks directly to Zeebe via the existing client credentials.
- The endpoint must be publicly reachable (or tunneled) so the emailed link works; environments need to set `user.confirmation.base-url` accordingly.
- We keep message semantics explicit in BPMN (the catch event waits on `UserId`), and other services can still subscribe to confirmation events later by tapping into Zeebe listeners instead of Kafka.
