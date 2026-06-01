= Architecture <architecture>

This chapter describes the system architecture of CryptoFlow. It begins with the service topology and the two main end-to-end flows, then covers the event-driven layer (Kafka topology), the process-oriented layer (BPMN workflows), the software-level architectural decisions, and closes with a summary of key architectural decision records.

== Service Topology

CryptoFlow is a distributed system comprising nine Spring Boot microservices that communicate exclusively through Apache Kafka events and Camunda 8 (Zeebe) process orchestration. No service makes synchronous REST or gRPC calls to another service for domain operations. The REST endpoints are exposed only for external client access.

#figure(
  image("figures/context-map-detailed.svg", width: 100%),
  caption: [Simplified platform topology showing deployable services grouped around the Kafka event backbone and Camunda orchestration backbone],
) <fig:system-overview>

@fig:system-overview expands the high-level context map (@fig:context-map) and deployment overview (@fig:deployment-overview) from @project-description. It intentionally groups the deployable services around two integration backbones instead of drawing every topic-level edge: Kafka carries the domain events and materialized read-model updates, while Camunda coordinates the onboarding and `placeOrder` workflows. The deployable services shown in the topology have the following responsibilities.

/ Market Data Service: Inbound adapter to Binance ticker streams. Publishes `CryptoPriceUpdatedEvent` records, hosts OHLC stream processing, and owns no database. The price-localization stream in ADR-0030 remains a documented target shape, while the implemented OHLC and portfolio valuation flows currently read `crypto.price.raw`.

/ Market Partial Book Ingestion Service: Inbound adapter to Binance partial book streams. Publishes replayable raw order-book depth events to `crypto.scout.raw`.

/ Market Order Scout Service: Kafka Streams processor for the market-scout pipeline. Consumes `crypto.scout.raw`, derives ask-side scout events, and publishes matchable asks for trading.

/ FX Rate Service: Reference-data producer that polls an external FX provider and publishes compacted `reference.fx.rate` events for display-currency conversion.

/ Coin Metadata Service: Reference-data producer that polls external coin metadata and publishes compacted metadata events for market-data enrichment.

/ Portfolio Service: Maintains portfolio and holding state in PostgreSQL. It keeps a local in-memory price cache derived from `crypto.price.raw`, exposes REST endpoints for valuation queries, updates holdings from approved-order events, and acts as a Camunda job worker for portfolio creation during onboarding.

/ Transaction Service: Owns the trading bounded context (ADR-0020). It deploys the `placeOrder.bpmn` process, validates incoming orders against a replicated read-model of confirmed users, matches pending buy bids against Matchable Asks in a Kafka Streams topology, and publishes approved-order events via its transactional outbox for downstream portfolio updates.

/ User Service: Owns user accounts, confirmation links, and confirmation-state changes. It acts as a Camunda job worker for user preparation, creation, and invalidation during onboarding, publishes confirmed-user events for downstream consumers, and handles compensation by deleting users when the onboarding saga fails.

/ Onboarding Service: Dedicated saga orchestrator (ADR-0010) that deploys `userOnboarding.bpmn` to Zeebe and coordinates the registration flow across the user and portfolio contexts. It owns no persistent business data because the workflow state lives in the Zeebe engine.

The `shared-events` module shown in @fig:system-overview is not a runtime service. It is a shared Maven module that defines the Kafka event contracts consumed and produced by the participating services, ensuring compile-time consistency across the codebase (ADR-0005).

Supporting infrastructure includes a Kafka broker (KRaft mode), PostgreSQL 16, Kafka UI for monitoring, and pgAdmin for database administration, all provisioned via Docker Compose.

=== Onboarding Flow

The onboarding flow spans three services and one external system. The user fills out a registration form in Camunda Tasklist, which starts the `userOnboarding` process instance in Zeebe. Inside `user-service`, the `prepareUserWorker` generates a `userId`, persists a `PENDING` confirmation link, and builds the confirmation email content. The Camunda email connector sends the email via SMTP. The process then waits at an event-based gateway for either a confirmation click or a one-minute timeout.

If the user clicks the confirmation link, `user-service` receives the HTTP request on its `UserConfirmationController`, marks the link as `CONFIRMED`, publishes a `UserConfirmedEvent` to Kafka, and correlates a `Message_UserConfirmed` message to Zeebe. The process then fans out through a parallel gateway: `userCreationWorker` creates the user record in `user-service`'s database, while `portfolioCreationWorker` creates a portfolio record in `portfolio-service`'s database. Both branches must succeed for the saga to complete. If either fails, compensation handlers delete the already-created entity and publish a compensation event for the peer service (ADR-0011). If the timer fires instead, the `invalidateConfirmationWorker` marks the link as `INVALIDATED` and the process ends.

=== Trading Flow

The trading flow stays primarily within the trading bounded context, but the market decision is now fed by the Market Scout stream. A user submits an order through Camunda Tasklist, starting a `placeOrder` process instance. The `order-processing-worker` validates the user against the local confirmed-user read-model (ADR-0017), creates a `PENDING` transaction record, and publishes a `BuyBid` to `transaction.buy-bids`. In parallel, Market Scout publishes `MatchableAsk` records derived from Binance partial-book snapshots to `crypto.scout.matchable-asks`. A Kafka Streams topology in `transaction-service` matches bids and asks by symbol and emits `transaction.order-matched` when the event-time, price, quantity, and allocation rules pass.

The process waits at an event-based gateway for either an order-matched event (correlated by `transactionId`) or a timeout. On a match, the `approveOrderWorker` writes both the `APPROVED` status and an outbox row in a single database transaction (ADR-0014). The `publishOrderApprovedWorker` then publishes the outbox entry to Kafka and marks it as published. The Camunda email connector notifies the user that the order was executed.

The portfolio update happens outside the orchestrated flow: `portfolio-service` independently consumes the `OrderApprovedEvent` from Kafka and updates holdings via `upsertHolding()`, protected by an idempotent consumer guard (ADR-0016). This separation is deliberate — the order approval is the terminal business event in the trading context, and the portfolio propagation is an eventual downstream consequence (ADR-0013, ADR-0015).

If the `approveOrderWorker` or `publishOrderApprovedWorker` encounters a deterministic failure (e.g., a missing transaction record or outbox row), it throws a typed BPMN error that routes the instance to an operations user task for human investigation (ADR-0018). After the operator resolves the task, the flow re-enters the happy path rather than terminating: an approval failure loops back to the approve step, while a publication failure skips forward to the notification step because the approved-order event has already been published and propagated to the portfolio context downstream (ADR-0035).

== Event-Driven Architectural Parts

Domain events, reference-data updates, and derived stream-processing events flow through Kafka. @fig:kafka-topology visualizes the current topology as implemented in the codebase, and @tab:kafka-topics summarizes the topic-level configuration.

#figure(
  image("figures/kafka-topology-render.svg", width: 100%),
  caption: "Kafka topic topology rendered from the current implementation",
) <fig:kafka-topology>

#figure(
  caption: "Kafka topic configuration",
  text(size: 7.5pt)[
    #table(
      columns: (1.55fr, 0.45fr, 0.9fr, 0.85fr, 2.4fr),
      inset: 2.5pt,
      [*Topic*], [*Partitions*], [*Retention / cleanup*], [*Message key*], [*Purpose*],
      [`crypto.price.raw`], [3], [1 hour], [`symbol`], [Live Binance ticker prices],
      [`crypto.price.raw.DLT`], [1], [1 hour], [Original key], [Dead-letter stream for failed raw price records],
      [`transaction.order.approved`], [3], [1 hour], [`trans-`#linebreak()`actionId`], [Approved orders consumed by Portfolio and valuation streams],
      [`transaction.buy-bids`], [3], [1 hour], [`symbol`], [Buy bids emitted by the place-order worker for matching],
      [`transaction.order-matched`], [3], [1 hour], [`trans-`#linebreak()`actionId`], [Matching decisions correlated back into Camunda],
      [`user.confirmed`], [3], [Log-compacted], [`userId`], [Confirmed-user read-model for Trading],
      [`user.display-currency`], [1], [Log-compacted], [`userId`], [Per-user Display Currency read-model for Portfolio and Trading],
      [`reference.fx.rate`], [1], [Log-compacted], [`currencyPair`], [FX-rate reference table],
      [`reference.crypto.metadata`], [1], [Log-compacted], [`symbol`], [Coin metadata for OHLC enrichment],
      [`crypto.scout.raw`], [3], [5 min / size-bounded], [`symbol`], [Raw Binance partial-book depth events],
      [`crypto.scout.ask-quotes / matchable-asks / ask-opportunities / window-summary`], [3], [5 min / size-bounded], [`symbol`], [Market Scout derived streams, including the cross-service ask contract for Trading],
      [`crypto.ohlc.1m / 5m / 1h`], [3], [7 / 30 / 365 days], [`symbol`], [Closed OHLC bars emitted after window close and grace],
      [`portfolio.value.updated`], [3], [Log-compacted], [`userId`], [Current portfolio value from the valuation topology],
      [`crypto.portfolio.compensation / crypto.user.compensation`], [3], [1 hour], [`userId`], [Bidirectional onboarding rollback requests between User and Portfolio],
    )
  ],
) <tab:kafka-topics>

The producer/consumer relationships are:

#figure(
  caption: "Kafka producers and consumers by service",
  table(
    columns: (auto, 1fr, 1fr),
    [*Service*], [*Produces to*], [*Consumes from*],
    [Market Data], [`crypto.price.raw`, `crypto.ohlc.*`], [`crypto.price.raw`, `reference.crypto.metadata`],
    [Partial Book Ingestion], [`crypto.scout.raw`], [--],
    [Market Order Scout], [`crypto.scout.ask-quotes`, `crypto.scout.matchable-asks`, `crypto.scout.ask-opportunities`, `crypto.scout.window-summary`], [`crypto.scout.raw`],
    [FX Rate], [`reference.fx.rate`], [--],
    [Coin Metadata], [`reference.crypto.metadata`], [--],
    [Portfolio], [`crypto.user.compensation`, `portfolio.value.updated`], [`crypto.price.raw`, `transaction.order.approved`, `crypto.portfolio.compensation`, `reference.fx.rate`, `user.display-currency`],
    [Transaction], [`transaction.buy-bids`, `transaction.order-matched`, `transaction.order.approved`], [`crypto.price.raw`, `transaction.buy-bids`, `crypto.scout.matchable-asks`, `transaction.order-matched`, `user.confirmed`, `reference.fx.rate`, `user.display-currency`],
    [User], [`crypto.portfolio.compensation`, `user.confirmed`, `user.display-currency`], [`crypto.user.compensation`],
  ),
) <tab:kafka-producers-consumers>

@tab:kafka-topics captures the topic-level configuration, while @tab:kafka-producers-consumers shows which service publishes and consumes each stream. The onboarding service is intentionally absent because it coordinates via Zeebe rather than Kafka. Topic cleanup is deliberately mixed: raw and matching streams use short delete retention, reference data and current-value streams are compacted caches, and OHLC bars retain longer interval-specific histories. The partition key strategy is topic-specific: market and scout streams use normalized symbol keys; `transaction.order.approved` and `transaction.order-matched` use `transactionId`; user-related topics use `userId`; FX rates use directed currency-pair keys such as `USDCHF`; and the DLT preserves the failed record's original Kafka key.

=== Broker, Producer, and Consumer Configuration

Beyond the topic layout, the Kafka layer is configured at three levels: broker, producer, and consumer. @tab:kafka-broker-config, @tab:kafka-producer-config, and @tab:kafka-consumer-config summarize the default settings and the deliberate deviations introduced by the second-half stream-processing work.

#show figure:set block(breakable: true)

#figure(
  caption: "Kafka broker configuration (Docker Compose)",
  table(
    columns: (auto, auto, auto),
    [*Property*], [*Value*], [*Rationale*],
    [`process.roles`], [`broker,controller`], [Single-node KRaft mode — no Zookeeper dependency],
    [`auto.create.topics.enable`], [`false`], [Topics are declared programmatically via Spring `NewTopic` beans, preventing typos or misconfigured producers from silently creating unintended topics],
    [`offsets.topic.replication.factor`], [`1`], [Required for single-broker operation],
    [`log.retention.hours`], [`1`], [Sufficient for real-time price streaming; consumers that fall behind lose events. Domain state is persisted in PostgreSQL, so Kafka is not the system of record],
    [`log.retention.bytes`], [`100 MB`], [Per-partition cap that prevents disk exhaustion in development],
    [`log.cleanup.policy`], [`delete`], [Default for raw and transient streams. Reference-data and current-value topics override to `compact` at topic level],
  ),
) <tab:kafka-broker-config>

#figure(
  caption: "Kafka producer configuration",
  table(
    columns: (1.25fr, 1.2fr, 2.7fr),
    [*Scope / Property*], [*Value*], [*Rationale*],
    [Default producer `acks`], [`all`], [Market-data, partial-book, reference-data, and Avro producers request all in-sync replicas. With a single broker this is functionally equivalent to `acks=1`, but the setting is forward-compatible with a replicated deployment (ADR-0001)],
    [Default key serializer], [`StringSerializer`], [Message keys are plain strings: symbols, user ids, transaction ids, or directed currency-pair keys],
    [Legacy/domain value serializer], [`JsonSerializer`], [Raw replay topics and original domain events remain readable JSON without type headers (ADR-0003)],
    [Derived cross-service value serializer], [`KafkaAvro-`#linebreak()`Serializer` / `SpecificAvroSerde`], [`FxRate`, `CoinMetadata`, `Ohlc`, `PortfolioValue`, and `UserDisplayCurrencyUpdated` use Avro with Schema Registry (ADR-0032)],
    [Scout-local derived serializer], [Registryless Avro serde], [`AskQuote`, `AskOpportunity`, `ScoutWindowSummary`, and the shared `MatchableAsk` contract use generated Avro classes without Schema Registry],
  ),
) <tab:kafka-producer-config>

#figure(
  caption: "Kafka consumer configuration",
  table(
    columns: (1.45fr, auto, 2.35fr),
    [*Scope / Property*], [*Value*], [*Rationale*],
    [Listener offset reset], [`earliest`], [New consumer groups replay from the oldest retained record. Validated in the consumer offset experiments (@results): `latest` silently skips retained history],
    [Listener auto commit], [`false`], [Offsets are committed after processing, not on poll. Prevents the consumer from advancing past records it has not yet processed],
    [JSON price listeners], [`ErrorHandling-`#linebreak()`Deserializer` + DLT], [Malformed price records are caught at deserialization and, after retries, published to `crypto.price.raw.DLT` so one poison pill does not block the partition],
    [Compensation listeners], [JSON deserializer + retry], [Compensation events are idempotent and retryable; they do not currently route to a DLT],
    [Avro/reference listeners], [`KafkaAvro-`#linebreak()`Deserializer`], [FX-rate and display-currency consumers use dedicated Schema Registry-aware factories],
    [Kafka Streams apps], [`earliest` + `LogAndContinue-`#linebreak()`ExceptionHandler`], [A fresh Streams application can rebuild retained state, while deserialization failures in stream tasks are logged and skipped instead of blocking the topology],
  ),
) <tab:kafka-consumer-config>

The configuration is intentionally not uniform anymore. The first-half services still use JSON for raw and domain events, while the second-half additions introduced Schema Registry-backed Avro for cross-service derived events and registryless Avro for scout-local derived streams. The same distinction appears on the consumer side: listener containers, Avro consumers, and Kafka Streams applications each use the error-handling model that fits their topic ownership and replay semantics.

*Single-broker trade-off.* The current deployment runs a single Kafka broker with no replication. This means that `acks=all` provides no durability advantage over `acks=1`. The experiments in @results demonstrate this directly: data loss under `acks=1` only occurs when a leader crashes before followers replicate, and with one broker there are no followers. The configuration is a conscious development-environment choice (ADR-0001): the architecture and code are designed for a replicated cluster, but the Docker Compose stack prioritizes simplicity over fault tolerance. A production deployment would require a multi-broker cluster with `replication.factor >= 3` and `min.insync.replicas = 2` to realize the durability guarantees that `acks=all` is designed to provide.

== Process-Oriented Architectural Parts

CryptoFlow uses Camunda 8 / Zeebe (ADR-0008) to orchestrate the two long-running business processes described above. This section shows the BPMN models and explains the modeling decisions behind them.

=== Commands, Events, and Workers

CryptoFlow distinguishes three interaction primitives in its BPMN models, each with a fixed naming convention and distinct runtime semantics summarized in @tab:bpmn-primitives. Commands and workers share an imperative naming style but differ at runtime: Zeebe invokes a worker over gRPC and halts the instance on failure so the error can be caught by a boundary event (ADR-0018, see @fig:placeorder-fairy-tale-saga), whereas a command dispatches a message and the downstream consumer acts autonomously without reporting back to the engine. This convention is applied consistently in both `userOnboarding.bpmn` and `placeOrder.bpmn`.

#figure(
  caption: "Naming conventions and runtime semantics for BPMN interaction primitives",
  table(
    columns: (auto, 0.6fr, 0.8fr, 1.2fr),
    [*Primitive*], [*BPMN element*], [*Naming convention*], [*Runtime semantics*],
    [Command], [Send task], [verb + subject (imperative); job type suffix `Command`], [Orchestrator dispatches a message and continues. Downstream consumer acts autonomously; Zeebe receives no acknowledgement],
    [Event], [Message intermediate catch event], [subject + verb (past tense); message reference suffix `Event`], [Correlated fact the process waits for. Zeebe durably suspends the instance and resumes it when a matching message arrives],
    [Worker], [Service task], [verb + subject (imperative); job type suffix `Worker`], [Zeebe invokes the worker over gRPC with retries. Deterministic failures halt the instance at that step and can be caught by boundary events],
  ),
) <tab:bpmn-primitives>
#show figure:set block(breakable: false)

#pagebreak()
=== User Onboarding Process

The `userOnboarding.bpmn` process, deployed by the onboarding service, implements a Parallel Saga (ADR-0010) that coordinates user and portfolio creation across two bounded contexts.

#figure(
  image("figures/userOnboarding-bpmn.png", width: 100%),
  caption: [User onboarding BPMN process with parallel saga, confirmation wait, and compensation paths],
) <fig:onboarding-parallel-saga>

#figure(
  image("figures/onboarding-sequence.svg", width: 100%),
  caption: [Onboarding runtime sequence: confirmation, parallel creation, and compensation. The compensation branch is drawn in one direction; the mirror path applies when the user-creation branch is the failing one],
) <fig:onboarding-sequence>

#figure(
  image("figures/user-confirmed-readmodel-sequence.svg", width: 85%),
  caption: [Supporting detail: `UserConfirmedEvent` propagation into the `transaction-service` confirmed-user projection, enabling later order placement to validate users locally (ADR-0017)],
) <fig:user-confirmed-readmodel-sequence>

@fig:onboarding-parallel-saga shows the orchestrated BPMN shape, while @fig:onboarding-sequence shows the core runtime collaboration. A parallel creation and compensation mediated by the compensation Kafka topics (ADR-0011). The cross-cutting read-model propagation triggered by the confirmation step is kept out of @fig:onboarding-sequence to preserve focus; @fig:user-confirmed-readmodel-sequence shows it as a dedicated detail. Its structure reflects three key modeling decisions:

*Event-based confirmation wait.* After the confirmation email is sent, the process suspends at an event-based gateway rather than polling or blocking a thread. Zeebe durably persists the waiting state, so the process can survive service restarts during the wait. The one-minute timer boundary ensures that abandoned registrations terminate cleanly by marking the confirmation link as `INVALIDATED` (ADR-0010).

*Parallel gateway for cross-context creation.* After confirmation, a parallel gateway fans out to `userCreationWorker` (user-service) and `portfolioCreationWorker` (portfolio-service). Both execute their own local ACID transaction in their own bounded context. The saga proceeds only when both branches report their outcome. This models the Parallel Saga pattern from Lecture 5: communication is asynchronous, consistency is eventual, and coordination is centralized in one orchestrator (ADR-0010).

*Flag-driven completion and compensation branches.* Both workers always complete their Zeebe jobs successfully and communicate the outcome through boolean flags (`isUserCreated`, `isPortfolioCreated`) rather than throwing BPMN errors. This is formalized in ADR-0012: throwing errors would short-circuit the flow and bypass the exclusive gateways that route to the compensation paths modeled in ADR-0011. If either flag is `false`, the BPMN routes to compensation handlers that delete the already-created entity and publish an event-carried compensation request for the peer service. The compensation events carry all necessary state (userId, userName, email, portfolioId) so the receiving service can execute the rollback without a synchronous callback.

=== Place Order Process

The `placeOrder.bpmn` process (see @fig:placeorder-fairy-tale-saga), deployed by the transaction service, implements a Fairy Tale Saga (ADR-0013) that keeps synchronous service tasks inside the trading context but accepts eventual consistency at the boundary to the portfolio context.

#figure(
  image("figures/placeOrder-bpmn.png", width: 100%),
  caption: [Place order BPMN process with Kafka-backed matching, timeout handling, downstream publication, and operations tasks that loop the resolved instance back into the happy path (ADR-0035)],
) <fig:placeorder-fairy-tale-saga>

#figure(
  image("figures/placeOrder-sequence.svg", width: 90%),
  caption: [Place order runtime sequence: local user validation, Kafka-backed matching wait, approval, publication, and downstream portfolio update],
) <fig:placeorder-sequence>

#figure(
  image("figures/outbox-sequence.svg", width: 90%),
  caption: [Supporting detail: transactional outbox mechanics. `approveOrderWorker` writes the APPROVED status and the outbox row in one local transaction; `publishOrderApprovedWorker` publishes and marks the row; the `OutboxScheduler` republishes orphaned rows (ADR-0014)],
) <fig:outbox-sequence>

@fig:placeorder-fairy-tale-saga shows the orchestrated BPMN shape, while @fig:placeorder-sequence shows the core runtime collaboration. This includes the downstream `portfolio-service` consumer that is deliberately outside the orchestrated flow (ADR-0013, ADR-0015) and therefore not visible in the BPMN. The outbox write/publish/recover mechanics are kept out of @fig:placeorder-sequence to preserve focus; @fig:outbox-sequence shows them as a dedicated detail. Its structure reflects the following modeling decisions:

*Event-based matching wait.* The process suspends at an event-based gateway while the transaction matching topology waits for a compatible `MatchableAsk`. When `transaction-service` consumes a `transaction.order-matched` event, it correlates the Camunda message by `transactionId`. This wait is of non-deterministic duration. It may last seconds or never terminate. Zeebe durably suspends the instance without holding a distributed lock or database connection (ADR-0013). A 35-second timer mirrors the 30-second matching window plus a five-second processing and retention margin: if no match occurs, the order is rejected and the user is notified.

==== Matching Extension

The original `placeOrder` flow matched pending orders against the latest ticker price held inside `transaction-service`. The stream-processing extension keeps the BPMN shape and the Fairy Tale Saga boundary intact, but replaces that simplified price check with a bid/ask matching pipeline. A placed order becomes a `BuyBid` event, `market-order-scout-service` supplies `MatchableAsk` events derived from Binance partial-book data, and a Kafka Streams topology in `transaction-service` emits `transaction.order-matched` when a bid can be allocated to an ask within the configured event-time validity window.

At the architecture level, the important point is separation of concerns: Kafka Streams owns the market-event matching decision, while Camunda still owns the business workflow that approves, rejects, notifies, and publishes the approved-order event through the outbox. The detailed topology, state stores, event-time rules, and allocation semantics are described in @kafka-streams-extensions.

*Transactional outbox for reliable publication.* The approval path uses two sequential workers. `approveOrderWorker` writes both the `APPROVED` status and an outbox row in a single local database transaction. `publishOrderApprovedWorker` then reads and publishes the outbox entry to Kafka. A scheduled safety net republishes any rows that remain unpublished after a crash (ADR-0014). This guarantees that an approved order does not silently miss the event that must later update the portfolio.

*Human escalation for deterministic failures.* If the approval or publication step encounters a deterministic failure that automatic retries cannot resolve (e.g., a missing transaction record or outbox row), the worker throws a typed BPMN error. An interrupting boundary event routes the instance to an operations user task in Camunda Tasklist, where the operator sees the full order context and must document the resolution before closing the task (ADR-0018). After resolution the process re-enters the happy path rather than terminating (ADR-0035): an approval error loops back to the approve step so the atomic approve-with-outbox write can retry, while a publication error skips forward to the executed-email step because the approved-order event has already been published and the portfolio update is choreographed downstream, leaving nothing for the process to revert. A premature close simply re-raises the same task, so the escalation stays auditable and self-healing instead of retrying indefinitely or failing silently.

*Eventual portfolio propagation.* The portfolio update is deliberately not part of the orchestrated flow. After the outbox event is published to Kafka, `portfolio-service` consumes `OrderApprovedEvent` independently and updates holdings in its own ACID boundary, protected by an idempotent consumer guard (ADR-0016). The executed email confirms the order approval — the business event — not the portfolio propagation, which is a downstream consequence accepted as eventually consistent (ADR-0015).

== Software Architectural Parts

This section covers the software-level decisions that support the event-driven and process-oriented architecture above. These patterns were already familiar from prior coursework (ASSE) and are therefore treated concisely.

=== Microservice Decomposition

CryptoFlow is implemented as independently deployable Spring Boot 3.5 services on Java 21. Each service belongs to a bounded context and communicates with other services exclusively through Kafka and Zeebe. REST endpoints are exposed only for external client access, not for inter-service calls (ADR-0001).

=== Hexagonal Architecture

The services follow the same internal structure where applicable, separating the business core from technical adapters:

- `domain/` contains the domain model and invariants.
- `application/` contains use-case logic and the ports that the core depends on.
- `adapter/in/` contains inbound adapters: REST controllers, Kafka listeners, Camunda job workers, or the Binance WebSocket entry.
- `adapter/out/` contains outbound adapters: JPA repositories, Kafka producers, and external clients.

This separation ensures that transport, workflow-engine, and persistence details remain replaceable without moving domain rules into framework code.

=== Data Ownership and Persistence

Each stateful service owns a dedicated PostgreSQL 16 database (ADR-0019): `user-service` owns `user_service_db`, `portfolio-service` owns `portfolio_service_db`, and `transaction-service` owns `transaction_service_db`. No service reads from or writes to another service's tables. Cross-service references use opaque identifiers, not foreign keys.

Schema changes are managed through Flyway versioned migrations. Hibernate runs in `validate` mode. This means that it verifies the entity-to-schema mapping at startup but never modifies the database (ADR-0007). Cross-service consistency is achieved through the patterns described above: Kafka events, replicated read-models, the transactional outbox, and orchestrated sagas.

=== Shared Event Contracts

Event schemas are defined once in the `shared-events` Maven module (ADR-0005). All producing and consuming services depend on it at compile time, ensuring type-safe event contracts. The module contains Java records, Avro schemas, and serialization dependencies but no business logic. Schema changes are atomic: a single commit updates the contract and all affected consumers. New cross-service derived events use Avro with Confluent Schema Registry per ADR-0032; raw replay topics remain JSON.

== Key Architectural Decisions

The repository contains thirty-five accepted Architectural Decision Records (ADRs) in `docs/adrs`, excluding the template record. The most significant decisions are:

- *ADR-0001*: Kafka as the sole inter-service communication channel — no synchronous REST between services.
- *ADR-0002*: Event-Carried State Transfer for price data, enabling the portfolio service to answer queries without calling the market data service.
- *ADR-0008*: Camunda 8 (Zeebe) for process orchestration, chosen for its partitioned log, stateless worker model, and connector templates that keep Kafka and SMTP integration inside the BPMN model.
- *ADR-0010*: A dedicated onboarding service as saga orchestrator, separating the cross-context coordination concern from the participating services.
- *ADR-0011*: Event-carried compensation via Kafka for cross-service rollback, maintaining loose coupling even during failure handling.
- *ADR-0012*: Flag-driven completion for Camunda workers, ensuring BPMN compensation branches are always reachable.
- *ADR-0013*: Fairy Tale Saga for the placeOrder workflow, accepting eventual cross-service consistency to avoid distributed locks over a non-deterministic wait.
- *ADR-0014*: Transactional Outbox for reliable publication of approved-order events, preventing silent data loss between database commit and Kafka publication.
- *ADR-0017*: Replicated read-model for autonomous user validation at order placement, avoiding synchronous cross-service calls.
- *ADR-0018 / ADR-0035*: Human escalation for deterministic workflow failures, amended so operations resolution loops back into the `placeOrder` happy path instead of terminating the process.
- *ADR-0019*: Database per service for stateful bounded contexts, preserving independent deployment and schema ownership.
- *ADR-0020*: Transaction-service as sole owner of the trading bounded context, keeping order execution concerns isolated from user and portfolio management.
- *ADR-0021 to ADR-0025*: Market Scout uses Binance Partial Book Depth Streams as its replayable raw input, keeps raw events as JSON, derives ask-side Avro events, splits ingestion from scout processing, accepts a new Kafka Streams application id after the split, and enriches derived ask events with best-ask and notional features.
- *ADR-0026 / ADR-0027*: `MatchableAsk` is the narrow cross-service Avro contract from Market Scout to Trading, and bid/ask matching is implemented as a transaction-service Kafka Streams topology with a 30-second event-time validity window and price-time priority.
- *ADR-0028 to ADR-0030*: Display Currency is user-owned presentation data propagated through a compacted Kafka topic; FX rates live in a Reference Data bounded context; localized prices are the ADR-locked stream-table join target once the clean-price stream is available.
- *ADR-0031 / ADR-0033*: OHLC bars are emitted venue-native in USDT as closed bars and enriched with coin metadata through a GlobalKTable join, leaving display-currency conversion to read time.
- *ADR-0032*: New cross-service derived events use Avro with Confluent Schema Registry, while established raw JSON topics and registryless Market Scout Avro topics remain unchanged.
- *ADR-0034*: Portfolio valuation runs as a Kafka Streams topology inside `portfolio-service`, rebuilding holdings and values from event streams and exposing an interactive-query endpoint alongside the Postgres-backed read model.
