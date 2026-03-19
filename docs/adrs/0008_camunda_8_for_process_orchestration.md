# 8. Adopt Camunda 8 (Zeebe) as the process orchestration engine

Date: 2026-03-15

## Status

Accepted. Partially supersedes [ADR-0001](0001_kafka_as_sole_inter_service_communication.md) —
Kafka remains the inter-service event bus for domain events; Zeebe is introduced as a
complementary coordination channel for orchestrated process workflows.

## Context

CryptoFlow needs long-running, multi-step workflows (order placement, user onboarding, future
automated trading) that involve human interaction and react to Kafka price events. Pure
choreography via Kafka lacks a process state authority, makes error compensation ad hoc, and
requires custom tooling for visibility.

**Camunda 7 / Operaton** embeds the engine in the application, stores process state in the
application database, and requires custom client code for every Kafka or SMTP interaction.
Horizontal scaling is possible but operationally complex.

**Camunda 8 / Zeebe** runs as an external partitioned log; job workers are stateless gRPC
clients. Kafka and SMTP steps are connector templates in the BPMN model — no client code in
the service. A managed SaaS cluster eliminates broker operations.

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