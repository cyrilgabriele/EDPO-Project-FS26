# 8. Adopt Camunda 8 (Zeebe) as the process orchestration engine

Date: 2026-03-15

## Status

Accepted. Partially supersedes [ADR-0001](0001_kafka_as_sole_inter_service_communication.md) —
Kafka remains the inter-service event bus for domain events; Zeebe is introduced as a
complementary coordination channel for orchestrated process workflows.

## Context

CryptoFlow requires coordinated, multi-step workflows: user onboarding with email verification,
order placement across portfolio and transaction services, and future automated trading strategies
triggered by market-data events. These workflows are long-running, involve human interaction
(e.g. confirmation clicks), and must react to Kafka price streams.

Choreography via Kafka events alone becomes brittle at this level of complexity: there is no
single source of truth for process state, error compensation is ad hoc, and visibility into
in-flight instances requires custom tooling. A dedicated orchestration engine is therefore needed.

Two candidates were evaluated:

**Camunda 7 / Operaton** — Camunda 7 is no longer commercially supported by Camunda GmbH, but
Operaton is its actively maintained open-source community fork and keeps the engine viable.
It runs as an embedded engine inside the Spring Boot application, stores all process state in
the application's own relational database (PostgreSQL), and integrates through the well-established
`camunda-bpm-spring-boot-starter`. Every interaction with Kafka or an SMTP server requires a
custom Java delegate or external task worker that instantiates and manages the respective client
directly in application code. Clustering the job executor for horizontal scale is possible but
operationally complex and not designed for high-throughput fan-out scenarios.

**Camunda 8 / Zeebe** — a ground-up redesign built on a partitioned, append-only log (Zeebe
broker). Process state is owned by the broker, not the application database. Job workers are
lightweight gRPC clients that poll for work; they do not embed engine logic. Camunda 8 ships
a rich connector framework: Kafka topics and SMTP delivery are configured as reusable connector
templates directly in the BPMN model, without writing client code in the service. A managed
SaaS cluster eliminates broker operations entirely.

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

- **Horizontal scalability:** Zeebe's partitioned log scales out to handle high-frequency process
  instantiation (e.g. one process instance per market alert) without the bottleneck of a
  single relational job-lock table. Camunda 7/Operaton can achieve clustering but it is
  significantly more complex to operate and not the design target of that engine.
- **Connector-based integration:** Kafka topic subscriptions and SMTP delivery are configured
  as connector templates in the BPMN model rather than implemented as application code. This
  keeps service code focused on domain logic, though it shifts configuration and debugging
  to Camunda Operate rather than application logs.
- **Process state decoupled from application database:** Zeebe owns process variables and
  instance state. This avoids polluting the application schema with engine tables (as Camunda
  7/Operaton does), but it also means process state is not directly queryable via SQL and is
  not covered by application-level database backups.
- **Operational observability:** Camunda Operate provides real-time visibility into every
  in-flight and completed process instance, incident tracking, and variable inspection —
  capabilities that would require custom implementation against Camunda 7/Operaton's
  history tables.
- **BPMN as the authoritative process definition:** Business logic is expressed declaratively
  in versioned BPMN models, keeping diagrams readable across technical and non-technical
  stakeholders.
- **SaaS dependency:** The managed cluster introduces an external runtime dependency. Cluster
  availability and credential rotation must be accounted for in incident response and
  deployment configuration. Self-hosting Zeebe is an option but negates the operational
  simplicity argument.
- **Zeebe-specific expertise required:** Zeebe's execution model (stateless workers, message
  correlation by key, FEEL expression language) differs substantially from Camunda 7/Operaton's
  embedded engine and JUEL expressions. Teams already invested in the Camunda 7 programming
  model face a learning curve.