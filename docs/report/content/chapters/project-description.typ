#import "@preview/gallus-hsg:1.0.1": *

= Project Description <project-description>

CryptoFlow is a crypto portfolio simulation platform that demonstrates event-driven and process-oriented architecture patterns in a distributed microservice environment. The system allows users to register, manage cryptocurrency portfolios, and place simulated trading orders. This, all coordinated through asynchronous event streams and orchestrated business processes.

The Project release for this version of the reportcan be found on GitHub: 

https://github.com/cyrilgabriele/EDPO-Project-FS26/releases/tag/v1.0.0

== Domain and Goals <domain-and-goals>

The central goal of this project was to implement the concepts covered in the EDPO lectures in a self-chosen project. For that purpose, CryptoFlow was designed as a high-level cryptocurrency platform in which users can register, observe live market prices, manage simulated portfolios, and place simulated trading orders. The platform is intentionally not a production exchange; it serves as a concrete case study for applying the architectural and integration concepts from the course in one coherent end-to-end system.

=== Bounded Contexts

@fig:context-map shows the domain as a DDD context map. Five bounded contexts form the platform, each owned by a single service.

#figure(
  image("figures/context-map.jpeg", width: 62%),
  caption: [Context map of CryptoFlow showing bounded contexts, upstream/downstream relationships, and external systems],
) <fig:context-map>

/ Market Data: Upstream supplier for live prices. Ingests external Binance feeds through an Anti-Corruption Layer and publishes price events that flow downstream to Portfolio and Trading.
/ Portfolio: Downstream consumer of both price events and approved-order events. Owns holdings, valuation logic, and an in-memory price cache. Participates in the onboarding saga as a Camunda job worker.
/ Trading: Downstream consumer of price events and user-confirmation events. Owns order lifecycle, the transactional outbox, and a replicated read-model for user validation. Deploys the `placeOrder` BPMN process.
/ User Identity: Upstream supplier of confirmed-user events consumed by Trading. Owns user accounts, confirmation links, and identity state. Participates in the onboarding saga as a Camunda job worker.
/ Onboarding: Dedicated saga orchestrator with no persistent data of its own. Coordinates user and portfolio creation across bounded contexts via Camunda 8, keeping orchestration separate from domain ownership.

User Identity and Portfolio are connected through a Partnership relationship: bidirectional compensation events allow each side to roll back the other during onboarding failures. All contexts share a common event schema through the `shared-events` Shared Kernel module, ensuring compile-time consistency.

=== Architecture Characteristics <architecture-characteristics>

The bounded contexts and flows described above impose a set of quality attributes that any architectural solution must satisfy. The worksheet below identifies seven driving characteristics derived from the domain requirements, marks the top three, and lists additional characteristics that were considered but not deemed critical.

#show figure: set block(breakable: true)
#figure(
  caption: "Architecture characteristics worksheet",
  table(
    columns: (1.8fr, 0.4fr, 3fr),
    [*Characteristic*], [*Top 3*], [*Rationale*],
    [Data integrity], [#sym.checkmark], [Domain entities transition through distinct lifecycle states and are referenced across bounded contexts. If a state change is recorded in one context but its downstream effect is lost, the contexts diverge from each other. The platform must guarantee that every state change is durably captured and propagated without silent loss.],
    [Fault tolerance], [#sym.checkmark], [Processes can span multiple bounded contexts that can fail independently after a peer has already succeeded. Some contexts also depend on external systems that may disconnect at any time. The system must handle partial failures, malformed messages, and service crashes without corrupting state or blocking other work.],
    [Availability], [#sym.checkmark], [Each bounded context must remain functional when its peers are temporarily unreachable. This is the characteristic the platform actively buys by accepting eventual consistency: ECST, replicated read-models, and compensation sagas exist so that Portfolio can value holdings while User is down, Trading can match orders while Portfolio lags, and no single failure cascades across contexts.],
    [Data consistency], [], [Business processes span multiple bounded contexts, yet there is no shared database. Rather than enforcing strict cross-context consistency as an architectural driver, the platform intentionally trades it for availability and converges to correct state eventually through ECST, sagas, and compensation events.],
    [Responsiveness], [], [External market conditions change continuously. The platform must reflect relevant state changes with minimal delay so that downstream consumers can operate on current information.],
    [Deployability], [], [Independently owned bounded contexts must be developable, testable, and releasable without coordinated rollouts. The local development environment must be reproducible and startable with minimal manual steps.],
    [Extensibility], [], [The platform evolves iteratively. New bounded contexts and event flows are added over time. The internal structure of each service must allow adapters and integration technologies to change without rewriting domain logic.],
  ),
) <tab:architecture-characteristics>
#show figure: set block(breakable: false)


*Others considered.* Scalability (relevant for a production exchange but not a driving concern for this educational platform), testability (desirable but did not constrain architectural choices), interoperability (only relevant at the Binance boundary), and recoverability (closely related to fault tolerance but not an independent driver).

=== Implemented Concepts

The following EDPO lecture concepts are implemented in CryptoFlow:

- *Event-driven communication* through Apache Kafka as the backbone for inter-service collaboration.
- *Event-Carried State Transfer (ECST)* for price replication, portfolio updates, compensation events, and replicated user-validation data.
- *Process orchestration* with Camunda 8 / Zeebe, using BPMN workflows to coordinate long-running processes.
- *Service autonomy through bounded contexts* with clear ownership, a database-per-service model, and a dedicated onboarding-service to avoid a process monolith.
- *Parallel Saga* for the onboarding workflow.
- *Fairy Tale Saga* for the `placeOrder` workflow.
- *Compensation mechanisms* for distributed onboarding failures.
- *Transactional Outbox* for reliable publication of approved-order events.
- *Idempotent consumer* handling for at-least-once event delivery in portfolio updates.
- *Replicated read-model* for local validation without synchronous cross-service calls.
- *Human intervention as a stateful resilience pattern* for deterministic workflow failures.

== System Overview

@fig:deployment-overview gives a high-level deployment view of CryptoFlow.

#figure(
  image("figures/deployment-overview.svg", width: 100%),
  caption: [High-level deployment overview showing the Docker Compose runtime, Spring Boot services, infrastructure, and external systems],
) <fig:deployment-overview>

Inside the Docker Compose boundary, five Spring Boot microservices communicate through Apache Kafka and persist state in service-owned PostgreSQL databases. Market Data and Onboarding are stateless; Portfolio, Transaction, and User each own a dedicated database. Kafka UI and pgAdmin provide developer-facing observability.

Outside the local runtime, three external systems integrate with the platform. Binance delivers real-time price feeds over WebSocket. Camunda 8 hosts the BPMN process engine, with services connecting as stateless gRPC workers. End users interact through REST endpoints exposed by Portfolio and Transaction, and through Camunda Tasklist for human-intervention tasks.

The two main end-to-end flows that define the platform from the outside are the onboarding flow, which creates a confirmed user together with a matching portfolio, and the trading flow, which matches pending orders against live market prices before propagating approved trades to the portfolio context. @architecture provides the detailed service-by-service architecture, event topology, and BPMN interaction model.

== Technology Stack

@tab:tech-stack summarises the technology choices. Where a technology was evaluated through a formal architectural decision, the corresponding ADR is referenced.

#figure(
  caption: "Technology stack",
  table(
    columns: (1.2fr, 0.8fr, 2.5fr),
    [*Technology*], [*ADR*], [*Rationale*],
    [Java 21 + Spring Boot 3.5], [--], [Provides the service runtime, dependency injection, and web layer. Chosen for team familiarity and broad Kafka/Camunda library support.],
    [Apache Kafka (Confluent 7.6, KRaft)], [@adr-0001], [Sole inter-service communication channel for domain events. KRaft mode removes the Zookeeper dependency. Topics are explicitly declared via Spring `@Bean` definitions.],
    [Camunda 8 / Zeebe (SaaS)], [@adr-0008], [Orchestrates multi-step BPMN processes. Services act as stateless gRPC job workers. SaaS deployment provides managed scalability and Operate dashboard.],
    [PostgreSQL 16 + Flyway], [@adr-0007, @adr-0019], [Stores persistent data for the Portfolio, User, and Transaction bounded contexts with one database per service. Flyway manages schema migrations; Hibernate runs in `validate` mode only.],
    [Docker Compose], [--], [Provisions the full local infrastructure stack (Kafka, PostgreSQL, Kafka UI, pgAdmin) and all five application services. Enables reproducible single-command startup.],
    [Binance WebSocket API], [@adr-0006], [Provides real-time cryptocurrency price feeds at no cost and without authentication. Keeps the market-data path fully event-driven end-to-end.],
    [Jackson JSON], [@adr-0003], [Standardised serialization for all Kafka messages. Readable payloads, no schema registry required. Trade-off is larger payloads and no broker-side schema validation.],
    [`shared-events` module], [@adr-0005], [Shared Maven module defining Kafka event contracts. Ensures compile-time consistency across all producing and consuming services.],
  ),
) <tab:tech-stack>
