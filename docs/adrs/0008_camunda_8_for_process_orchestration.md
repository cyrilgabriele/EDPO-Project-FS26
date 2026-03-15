# 8. Adopt Camunda 8 for CryptoFlow orchestration

Date: 2026-03-15
Author: Cyril Gabriele

## Status

Accepted

## Context

Upcoming BPMN workflows (user onboarding, automated trading, portfolio rebalancing) need to react directly to Kafka price streams 
and to fan out long-running user-specific processes whenever market conditions hit thresholds. 
Trading traffic can spike (multiple price alerts per second), so the orchestration layer must horizontally scale, stay in lockstep with Kafka, and deliver confirmation emails without building custom SMTP glue. 
The current `user-service` already uses Camunda 8 SaaS and ships BPMN models that rely on Camunda 8 email and Kafka connectors plus Zeebe job workers.

## Decision

Standardise on Camunda 8 (Zeebe) for all orchestration. BPMN models continue to be deployed through the `@Deployment` hook in user-service, 
job workers stay on `io.camunda.zeebe.spring`, and message correlation keeps using the Zeebe gRPC client against the managed Camunda 8 cluster so we can attach Kafka/email connectors directly inside the processes.

## Consequences

- **High-traffic readiness:** Zeebe's partitioned broker scales horizontally, so automated trading/rebalancing processes spawned by rapid Binance price changes keep up without blocking on a single relational job executor (the Camunda 7 model).
- **Kafka connector fit:** Camunda 8 ships Kafka connectors that subscribe/publish directly to the same topics already defined in CryptoFlow, letting BPMN steps react to events without bespoke bridge services.
- **Email automation:** The onboarding flow keeps its Camunda 8 email connector template (`io.camunda:email:1`), avoiding the need to maintain SMTP credentials or microservices for confirmation mails.
- **Operational focus:** Developers continue to invest in Zeebe-specific tooling (Operate, connectors). Switching to Camunda 7 would forfeit the managed SaaS cluster and require embedded engine operations we do not staff.
