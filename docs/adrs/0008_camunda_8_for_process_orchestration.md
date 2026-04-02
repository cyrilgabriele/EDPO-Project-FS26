# 8. Adopt Camunda 8 (Zeebe) as the process orchestration engine

Date: 2026-03-15

## Status

Accepted. Partially supersedes [ADR-0001](0001_kafka_as_sole_inter_service_communication.md) —
Kafka remains the inter-service event bus for domain events; Zeebe is introduced as a
complementary coordination channel for orchestrated process workflows.

## Context

CryptoFlow already contains two concrete orchestrated workflows: `userOnboarding` and
`placeOrder`. In `userOnboarding`, Camunda 8's out-of-the-box outbound email connector sends
the confirmation mail. In `placeOrder`, the same connector template is used for the order
executed and order rejected notifications. The ADR is therefore not just a generic technology
preference; it documents the engine that is already reflected in both BPMN models and in the
surrounding worker and message-correlation implementation.

If CryptoFlow were taken beyond the course project into production, the system would need to
scale for many concurrent onboarding and order instances reacting to Kafka price events. That
would likely require cloud deployment anyway. The Zeebe architecture discussed in Lecture 6
matches that direction and is also the basis for the consequences listed below: process state
is managed in an external partitioned log, workers remain stateless gRPC clients, and Operate
provides runtime visibility.

Compared with **Camunda 7 / Operaton**, which embeds the engine in the application, stores
process state in the application database, and would require more operational effort to scale,
**Camunda 8 / Zeebe** is the more suitable fit for this project. Kafka and SMTP steps can stay
in the BPMN model via connector templates instead of requiring separate application-level client
code for these orchestration concerns.

## Decision

Standardise on Camunda 8 (Zeebe) for all process orchestration across CryptoFlow. BPMN models
are deployed via the `@Deployment` hook in each service. Job workers use the
`io.camunda.zeebe.spring` client. Message correlation targets the managed Camunda 8 SaaS
cluster. Kafka and email integration is configured through Camunda 8 connector templates inside
the BPMN models; no application-level Kafka producer or SMTP client is written for these steps.

Kafka (ADR-0001) continues to carry all domain events between services. Zeebe handles process
state, step coordination, and incident management within orchestrated workflows. The two channels
are complementary and operate at different layers of the architecture.

## Consequences

- **Scales to high-frequency automated trading:** Zeebe's partitioned log sustains thousands of
  concurrent process instances without job-lock contention — future-proof for market-event-driven
  automated order execution.
- **Many open orders in parallel:** Each `placeOrder` instance waits independently for its price
  match via `transactionId` correlation. No shared polling table or in-memory workaround required,
  regardless of how many concurrent open offers exist.
- **Services stay focused on domain logic:** Kafka and SMTP steps are connector templates in the
  BPMN model — no notification client code in the application.
- **Application database stays clean:** Zeebe owns process state; the application schema only
  holds domain data (portfolios, transaction records).
- **Visibility into every order:** Camunda Operate shows all in-flight and completed instances,
  variables, and incidents — useful for debugging stuck or rejected orders.
- **SaaS dependency:** Managed cluster availability and credential rotation must be accounted for
  in operations.
- **Zeebe-specific learning curve:** Stateless workers, message correlation, and FEEL differ from
  the Camunda 7 model.
