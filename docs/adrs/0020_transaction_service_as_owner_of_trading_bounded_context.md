# ADR-0020: Transaction-Service as Sole Owner of the Trading Bounded Context

**Date**: 2026-04-02

## Status

Accepted

## Context

Order placement, pending-order tracking, price matching, approval or rejection, and reliable
publication of approved orders belong to one cohesive domain: trading.

The ADR set already documents the workflow shape and reliability mechanics of this area
(ADR-0013 to ADR-0018). However, the decision of introducing one single responsible service for this domain is done here. 
Splitting trading responsibilities across `portfolio-service`, `user-service`, or
`onboarding-service` would blur bounded contexts and increase coupling through shared state and
mixed responsibilities.

## Decision

`transaction-service` is the sole owner of the trading bounded context.

It owns:

- the `placeOrder.bpmn` process and its Camunda workers
- transaction lifecycle state (`PENDING`, `APPROVED`, `REJECTED`)
- pending-order matching against replicated market data
- reliable publication of `transaction.order.approved`
- trading persistence tables such as `transaction_record`, `outbox_events`, and the local
  confirmed-user read model used for validation

Other services do not update trading tables directly. `portfolio-service` reacts to approved-order
events asynchronously; `user-service` provides confirmation state indirectly through
`user.confirmed`.

## Consequences

- Clear service boundary for trading behavior and invariants.
- `portfolio-service` remains a downstream projection owner, not an order-execution service.
- `user-service` remains the identity owner, not an order-validation endpoint.
- Order execution and portfolio updates are eventually consistent across service boundaries, as
  already accepted in ADR-0013 through ADR-0018.
- Introduces another deployable service and local persistence model, but keeps responsibility
  aligned with the domain.

## References

- ADR-0001 · ADR-0008 · ADR-0013 · ADR-0014 · ADR-0015 · ADR-0017 · ADR-0018
