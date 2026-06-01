#import "@preview/gallus-hsg:1.0.1": *

= Project Description <project-description>

CryptoFlow is a crypto portfolio simulation platform that demonstrates event-driven, stream-processing, and process-oriented architecture patterns in a distributed microservice environment. The system allows users to register, manage cryptocurrency portfolios, observe live market data, and place simulated trading orders, all coordinated through asynchronous event streams, materialized stream state, and orchestrated business processes.

The project release for this version of the report can be found on GitHub:

https://github.com/cyrilgabriele/EDPO-Project-FS26/releases/tag/v1.0.0

== Domain and Goals <domain-and-goals>

The central goal of this project was to implement the concepts covered in the EDPO lectures in a self-chosen project. For that purpose, CryptoFlow was designed as a high-level cryptocurrency platform in which users can register, observe live market prices, manage simulated portfolios, and place simulated trading orders. The platform is intentionally not a production exchange; it serves as a concrete case study for applying the architectural and integration concepts from the course in one coherent end-to-end system.

=== Bounded Contexts

@fig:context-map shows the domain as a DDD context map. The final platform is best understood as six bounded contexts: Market Data, Reference Data, Portfolio, Trading, User, and Onboarding.

#figure(
  image("figures/cmap.svg", width: 84%),
  caption: [Context map of CryptoFlow showing bounded contexts, upstream/downstream relationships, and external systems],
) <fig:context-map>

/ Market Data: Upstream supplier for live prices and market analytics, grouping three related ingest services:
  - *Live ticker feeds* — Ingests real-time Binance WebSocket price data and publishes price events downstream to Portfolio and Trading.
  - *Partial order-book* — Aggregates live bid/ask depth from Binance futures and derives Scout summary statistics via stateful Kafka Streams.
  - *OHLC aggregation* — Produces windowed candlestick bars enriched with coin metadata from the Reference Data context.
/ Reference Data: Slow-moving externally sourced facts for event enrichment, grouping two reference-data providers:
  - *FX rates* — Scheduled ingestion from Frankfurter, published as compacted topics for display-currency conversion downstream.
  - *Coin metadata* — Periodic ingestion from CoinGecko, available as a `GlobalKTable` for enriching closed OHLC bars.
/ Portfolio: Downstream consumer of both price events and approved-order events. Owns holdings, valuation logic, and an in-memory price cache. Participates in the onboarding saga as a Camunda job worker.
/ Trading: Downstream consumer of price events and user-confirmation events. Owns order lifecycle, the transactional outbox, and a replicated read-model for user validation. Deploys the `placeOrder` BPMN process.
/ User: Upstream supplier of confirmed-user events consumed by Trading. Owns user accounts, confirmation links, and identity state. Participates in the onboarding saga as a Camunda job worker.
/ Onboarding: Dedicated saga orchestrator with no persistent data of its own. Coordinates user and portfolio creation across bounded contexts via Camunda 8, keeping orchestration separate from domain ownership.

User and Portfolio are connected through a Partnership relationship: bidirectional compensation events allow each side to roll back the other during onboarding failures. All contexts share a common event schema through the `shared-events` Shared Kernel module, ensuring compile-time consistency.

=== Architecture Characteristics <architecture-characteristics>

The bounded contexts and flows described above impose a set of quality attributes that any architectural solution must satisfy. The worksheet below identifies seven driving characteristics derived from the domain requirements, marks the top three, and lists additional characteristics that were considered but not deemed critical.

#show figure: set block(breakable: false)
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

The following EDPO lecture concepts are implemented in CryptoFlow. They are grouped by the two main parts of the course so the report distinguishes process-oriented integration work from event-driven and stream-processing work.

==== Process-Oriented Concepts

- *Process orchestration* with Camunda 8 / Zeebe, using BPMN workflows to coordinate long-running processes.
- *Service autonomy through bounded contexts* with clear ownership, a database-per-service model, and a dedicated onboarding-service to avoid a process monolith.
- *Parallel Saga* for the onboarding workflow.
- *Fairy Tale Saga* for the `placeOrder` workflow.
- *Compensation mechanisms* for distributed onboarding failures.
- *Transactional Outbox* for reliable publication of approved-order events.
- *Idempotent consumer* handling for at-least-once event delivery in portfolio updates.
- *Replicated read-model* for local validation without synchronous cross-service calls.
- *Human intervention as a stateful resilience pattern* for deterministic workflow failures.

==== Event-Driven and Stream-Processing Concepts

- *Event-driven communication* through Apache Kafka as the backbone for inter-service collaboration.
- *Event-Carried State Transfer (ECST)* for price replication, portfolio updates, compensation events, and replicated user-validation data.
- *Stateless stream processing* for FX-rate ingestion, coin metadata ingestion, and Market Scout ask filtering/translation.
- *Stateful Kafka Streams processing* for bid/ask matching, OHLC windows, Market Scout summaries, and portfolio valuation.
- *Windowing, event-time timestamp extraction, grace periods, and suppression* for closed OHLC bars and market-scout summaries.
- *Joins and repartitioning* through OHLC metadata enrichment, portfolio valuation table-table joins, and portfolio value aggregation by user.
- *Interactive queries* for portfolio value and Market Scout dashboard state.
- *Schema-managed derived events* with Avro and Confluent Schema Registry for cross-service stream contracts.

== System Overview

@fig:deployment-overview gives a high-level deployment view of CryptoFlow.

#figure(
  image("figures/deployment-overview.svg", width: 100%),
  caption: [High-level deployment overview showing the Docker Compose runtime, Spring Boot services, infrastructure, and external systems],
) <fig:deployment-overview>

Inside the Docker Compose boundary, the Spring Boot services communicate through Apache Kafka and persist state in service-owned PostgreSQL databases where needed. Market and reference-data ingestion services are stateless; Portfolio, Transaction, and User each own a dedicated database. Kafka Streams applications materialize local RocksDB-backed state stores for matching, OHLC, Scout dashboard statistics, and portfolio valuation. Kafka UI and pgAdmin provide developer-facing observability.

Outside the local runtime, four external systems integrate with the platform. Binance delivers real-time ticker and partial-book feeds over WebSocket, Frankfurter provides FX rates, CoinGecko provides coin metadata, and Camunda 8 hosts the BPMN process engine with services connecting as stateless gRPC workers. End users interact through REST endpoints exposed by Portfolio and Transaction, and through Camunda Tasklist for human-intervention tasks.

The two main end-to-end flows that define the platform from the outside are the onboarding flow, which creates a confirmed user together with a matching portfolio, and the trading flow, which matches pending buy bids against ask liquidity derived from live order-book snapshots before propagating approved trades to the portfolio context. @architecture provides the service topology, event topology, and BPMN interaction model.

#pagebreak()
== Technology Stack

@tab:tech-stack summarises the technology choices. Where a technology was evaluated through a formal architectural decision, the corresponding ADR is referenced.

#figure(
  caption: "Technology stack",
  text(size: 8.7pt)[#table(
    columns: (1.25fr, 0.85fr, 2.4fr),
    inset: 3pt,
    [*Technology*], [*ADR*], [*Rationale*],
    [Java 21 + Spring Boot 3.5.11], [--], [Provides the service runtime, dependency injection, web layer, scheduling, JPA integration, and Kafka/Camunda adapters.],
    [Apache Kafka (Confluent 7.6, KRaft)], [@adr-0001], [Sole inter-service communication channel for domain events and stream inputs. Topics are explicitly declared via Spring `NewTopic` beans.],
    [Camunda 8 / Zeebe (SaaS)], [@adr-0008], [Orchestrates multi-step BPMN processes. Services act as stateless gRPC job workers. SaaS deployment provides managed scalability and Operate dashboard.],
    [PostgreSQL 16 + Flyway], [@adr-0007, @adr-0019], [Stores persistent data for the Portfolio, User, and Transaction bounded contexts with one database per service. Flyway manages schema migrations; Hibernate runs in `validate` mode only.],
    [Docker Compose], [--], [Provisions Kafka, Schema Registry, PostgreSQL, Kafka UI, pgAdmin, and all application services for reproducible local integration.],
    [Binance WebSocket APIs], [@adr-0006, @adr-0021], [Provides spot ticker data for prices and USD-M futures partial-book depth for Market Scout without request-time polling.],
    [Frankfurter FX API], [@adr-0029], [Provides scheduled USD-based FX reference data for display-currency conversion through compacted Kafka topics.],
    [CoinGecko API], [@adr-0033], [Provides slow-moving coin metadata used to enrich closed OHLC bars through a `GlobalKTable` join.],
    [Kafka Streams], [@adr-0022, @adr-0027, @adr-0031, @adr-0034], [Runs the continuously active topologies for Market Scout derivation, bid/ask matching, OHLC aggregation, and portfolio valuation.],
    [Confluent Schema Registry + Avro], [@adr-0032], [Provides schema-managed contracts for cross-service derived events, while raw replay topics stay JSON.],
    [Jackson JSON], [@adr-0003], [Standardised serialization for raw replay boundaries and original domain events. Readable payloads, but no broker-side schema validation.],
    [`shared-events` module], [@adr-0005], [Shared Maven module defining Kafka event contracts. Ensures compile-time consistency across all producing and consuming services.],
  )],
) <tab:tech-stack>
