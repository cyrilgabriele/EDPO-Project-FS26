# 10. Generate confirmation link via Zeebe worker

Date: 2026-03-15
Author: Cyril Gabriele

## Status

Accepted

## Context

We needed a UUID plus templated email body before invoking the connector-based "Send confirmation mail" task. Doing this inside the BPMN manually (expressions/scripts) isn’t supported, and pushing it back to the REST controller would duplicate logic outside the orchestrated flow.

## Decision

Introduce a dedicated Zeebe worker (`userPreparationWorker`) in `user-service` that executes right after the manual form task. It generates the UUID, computes the confirmation link using `user.confirmation.base-url`, stores `userCreationMailContent`, and hands both variables to the connector.

## Consequences

- Every process instance gets consistent link generation logic, versioned alongside the service.
- The BPMN stays declarative—no inline scripts or duplicated controller code—but we pay for another worker bean to maintain/test.
- Operate shows preparation failures explicitly, making troubleshooting easier than when everything happened inside the email task.
