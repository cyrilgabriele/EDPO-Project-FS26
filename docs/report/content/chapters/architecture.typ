= Architecture <architecture>

This chapter describes the system architecture of CryptoFlow. It begins with the service topology and the two main end-to-end flows, then covers the event-driven layer (Kafka topology), the process-oriented layer (BPMN workflows), the software-level architectural decisions, and closes with a summary of key architectural decision records.

== Service Topology

CryptoFlow is a distributed system comprising five Spring Boot microservices that communicate exclusively through Apache Kafka events and Camunda 8 (Zeebe) process orchestration. No service makes synchronous REST or gRPC calls to another service for domain operations. The REST endpoints are exposed only for external client access.

#figure(
  image("figures/context-map-detailed.svg", width: 100%),
  caption: [Platform-level service topology showing the five services, event contracts, external actors, and Camunda orchestration],
) <fig:system-overview>

@fig:system-overview expands the high-level context map (@fig:context-map) and deployment overview (@fig:deployment-overview) from @project-description. The five deployable services, the shared event-contract module, the external Binance feed, and the two orchestration entry points that interact with Camunda are shown below with their responsibilities.

/ Market Data Service: Inbound adapter to the Binance WebSocket API. Subscribes to real-time ticker streams for six cryptocurrency pairs and publishes `CryptoPriceUpdatedEvent` records to Kafka. The service is stateless and owns no database.

/ Portfolio Service: Maintains portfolio and holding state in PostgreSQL. It keeps a local in-memory price cache derived from `crypto.price.raw`, exposes REST endpoints for valuation queries, updates holdings from approved-order events, and acts as a Camunda job worker for portfolio creation during onboarding.

/ Transaction Service: Owns the trading bounded context (ADR-0020). It deploys the `placeOrder.bpmn` process, validates incoming orders against a replicated read-model of confirmed users, matches pending orders against live prices, and publishes approved-order events via its transactional outbox for downstream portfolio updates.

/ User Service: Owns user accounts, confirmation links, and confirmation-state changes. It acts as a Camunda job worker for user preparation, creation, and invalidation during onboarding, publishes confirmed-user events for downstream consumers, and handles compensation by deleting users when the onboarding saga fails.

/ Onboarding Service: Dedicated saga orchestrator (ADR-0010) that deploys `userOnboarding.bpmn` to Zeebe and coordinates the registration flow across the user and portfolio contexts. It owns no persistent business data because the workflow state lives in the Zeebe engine.

The `shared-events` module shown in @fig:system-overview is not a runtime service. It is a shared Maven module that defines the Kafka event contracts consumed and produced by the participating services, ensuring compile-time consistency across the codebase (ADR-0005).

Supporting infrastructure includes a Kafka broker (KRaft mode), PostgreSQL 16, Kafka UI for monitoring, and pgAdmin for database administration, all provisioned via Docker Compose.

=== Onboarding Flow

The onboarding flow spans three services and one external system. The user fills out a registration form in Camunda Tasklist, which starts the `userOnboarding` process instance in Zeebe. Inside `user-service`, the `prepareUserWorker` generates a `userId`, persists a `PENDING` confirmation link, and builds the confirmation email content. The Camunda email connector sends the email via SMTP. The process then waits at an event-based gateway for either a confirmation click or a one-minute timeout.

If the user clicks the confirmation link, `user-service` receives the HTTP request on its `UserConfirmationController`, marks the link as `CONFIRMED`, publishes a `UserConfirmedEvent` to Kafka, and correlates a `Message_UserConfirmed` message to Zeebe. The process then fans out through a parallel gateway: `userCreationWorker` creates the user record in `user-service`'s database, while `portfolioCreationWorker` creates a portfolio record in `portfolio-service`'s database. Both branches must succeed for the saga to complete. If either fails, compensation handlers delete the already-created entity and publish a compensation event for the peer service (ADR-0011). If the timer fires instead, the `invalidateConfirmationWorker` marks the link as `INVALIDATED` and the process ends.

=== Trading Flow

The trading flow stays primarily within the trading bounded context. A user submits an order through Camunda Tasklist, starting a `placeOrder` process instance. The `order-processing-worker` validates the user against the local confirmed-user read-model (ADR-0017), creates a `PENDING` transaction record, and begins matching against live prices from `crypto.price.raw`.

The process waits at an event-based gateway for either a price match (correlated by `transactionId`) or a one-minute timeout. On a match, the `approveOrderWorker` writes both the `APPROVED` status and an outbox row in a single database transaction (ADR-0014). The `publishOrderApprovedWorker` then publishes the outbox entry to Kafka and marks it as published. The Camunda email connector notifies the user that the order was executed.

The portfolio update happens outside the orchestrated flow: `portfolio-service` independently consumes the `OrderApprovedEvent` from Kafka and updates holdings via `upsertHolding()`, protected by an idempotent consumer guard (ADR-0016). This separation is deliberate — the order approval is the terminal business event in the trading context, and the portfolio propagation is an eventual downstream consequence (ADR-0013, ADR-0015).

If the `approveOrderWorker` or `publishOrderApprovedWorker` encounters a deterministic failure (e.g., a missing transaction record or outbox row), it throws a typed BPMN error that routes the instance to an operations user task for human investigation (ADR-0018).

== Event-Driven Architectural Parts

All domain events flow through Kafka. @fig:kafka-topology visualizes the current topology as implemented in the codebase, and @tab:kafka-topics summarizes the topic-level configuration.

#figure(
  image("figures/kafka-topology-render.svg", width: 100%),
  caption: "Kafka topic topology rendered from the current implementation",
) <fig:kafka-topology>

#figure(
  caption: "Kafka topic configuration",
  table(
    columns: (auto, auto, 1.1fr, 0.9fr, 2.4fr),
    [*Topic*], [*Partitions*], [*Retention / cleanup*], [*Message key*], [*Purpose*],
    [`crypto.price.raw`], [3], [1 hour], [`symbol`], [Live price ticks from Binance],
    [`crypto.price.raw.DLT`], [1], [1 hour], [Same as failed record], [Dead-letter stream for failed `crypto.price.raw` records after retries],
    [`transaction.order.approved`], [3], [1 hour], [`trans-`#linebreak()`actionId`], [Approved order events consumed by the portfolio service],
    [`user.confirmed`], [3], [Log-compacted], [`userId`], [Replicated read-model of confirmed users for the transaction service],
    [`crypto.portfolio.compensation`], [3], [1 hour], [`userId`], [Portfolio rollback requests from the user service],
    [`crypto.user.compensation`], [3], [1 hour], [`userId`], [User rollback requests from the portfolio service],
  ),
) <tab:kafka-topics>

The producer/consumer relationships are:

#figure(
  caption: "Kafka producers and consumers by service",
  table(
    columns: (auto, 1fr, 1fr),
    [*Service*], [*Produces to*], [*Consumes from*],
    [Market Data], [`crypto.price.raw`], [--],
    [Portfolio], [`crypto.user.compensation`], [`crypto.price.raw`, `transaction.order.approved`, `crypto.portfolio.compensation`],
    [Transaction], [`transaction.order.approved`], [`crypto.price.raw`, `user.confirmed`],
    [User], [`crypto.portfolio.compensation`, `user.confirmed`], [`crypto.user.compensation`],
  ),
) <tab:kafka-producers-consumers>

@tab:kafka-topics captures the topic-level configuration, while @tab:kafka-producers-consumers shows which service publishes and consumes each stream. The onboarding service is intentionally absent because it coordinates via Zeebe rather than Kafka. Except for the compacted `user.confirmed` topic, all topics inherit the broker's 1-hour development retention from Docker Compose. The partition key strategy is topic-specific: `crypto.price.raw` uses the trading symbol (e.g., `BTCUSDT`) with the deterministic `symbolIndex % numPartitions` mapping from ADR-0004; `transaction.order.approved` uses `transactionId`; `user.confirmed` and both compensation topics use `userId`; and the DLT preserves the failed record's original Kafka key.

=== Broker, Producer, and Consumer Configuration

Beyond the topic layout, the Kafka layer is configured at three levels: broker, producer, and consumer. @tab:kafka-broker-config, @tab:kafka-producer-config, and @tab:kafka-consumer-config summarize the settings and their rationale.

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
    [`log.cleanup.policy`], [`delete`], [Default for all topics except `user.confirmed`, which overrides to `compact` at topic level],
  ),
) <tab:kafka-broker-config>

#figure(
  caption: "Kafka producer configuration",
  table(
    columns: (1.2fr, auto, 2.4fr),
    [*Property*], [*Value*], [*Rationale*],
    [`acks`], [`all`], [The broker acknowledges only after all in-sync replicas confirm the write. With a single broker this is functionally equivalent to `acks=1`, but the setting is forward-compatible with a multi-broker deployment (ADR-0001)],
    [`key.serializer`], [`StringSerializer`], [Message keys are plain strings (symbol, userId, transactionId)],
    [`value.serializer`], [`JsonSerializer`], [Jackson JSON without type headers (ADR-0003). Readable payloads, no schema registry required],
  ),
) <tab:kafka-producer-config>

#figure(
  caption: "Kafka consumer configuration",
  table(
    columns: (1.4fr, auto, 2.2fr),
    [*Property*], [*Value*], [*Rationale*],
    [`auto.offset.reset`], [`earliest`], [New consumer groups replay from the oldest retained record. Validated in the consumer offset experiments (@results): `latest` silently skips retained history],
    [`enable.auto.commit`], [`false`], [Offsets are committed after processing, not on poll. Prevents the consumer from advancing past records it has not yet processed],
    [`value.deserializer`], [`ErrorHandling-`#linebreak()`Deserializer`], [Wraps `JsonDeserializer`. Malformed messages (poison pills) are caught at deserialization rather than crashing the consumer loop],
    [`error handler`], [DLT recovery], [After 3 attempts (2 retries at 500 ms fixed backoff), a failed record is published to `crypto.price.raw.DLT`. This prevents a single bad record from blocking the partition],
  ),
) <tab:kafka-consumer-config>

All producer configurations across services use the same settings. The `ErrorHandlingDeserializer` and DLT recovery are configured for the price-event consumers in `portfolio-service` and `transaction-service`. The compensation consumers in `user-service` and `portfolio-service` use the same offset and commit settings but do not currently route to a DLT, because compensation events are idempotent by design. A failed compensation attempt is retried on the next delivery rather than dead-lettered.

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

The `placeOrder.bpmn` process, deployed by the transaction service, implements a Fairy Tale Saga (ADR-0013) that keeps synchronous service tasks inside the trading context but accepts eventual consistency at the boundary to the portfolio context.

#figure(
  image("figures/placeOrder-bpmn.png", width: 100%),
  caption: [Place order BPMN process with price matching, timeout handling, and downstream publication],
) <fig:placeorder-fairy-tale-saga>

#figure(
  image("figures/placeOrder-sequence.svg", width: 90%),
  caption: [Place order runtime sequence: local user validation, price-match wait, approval, publication, and downstream portfolio update],
) <fig:placeorder-sequence>

#figure(
  image("figures/outbox-sequence.svg", width: 90%),
  caption: [Supporting detail: transactional outbox mechanics. `approveOrderWorker` writes the APPROVED status and the outbox row in one local transaction; `publishOrderApprovedWorker` publishes and marks the row; the `OutboxScheduler` republishes orphaned rows (ADR-0014)],
) <fig:outbox-sequence>

@fig:placeorder-fairy-tale-saga shows the orchestrated BPMN shape, while @fig:placeorder-sequence shows the core runtime collaboration. This includes the downstream `portfolio-service` consumer that is deliberately outside the orchestrated flow (ADR-0013, ADR-0015) and therefore not visible in the BPMN. The outbox write/publish/recover mechanics are kept out of @fig:placeorder-sequence to preserve focus; @fig:outbox-sequence shows them as a dedicated detail. Its structure reflects the following modeling decisions:

*Event-based price-match wait.* The process suspends at an event-based gateway waiting for a `price-matched` message correlated by `transactionId`. This wait is of non-deterministic duration. It may last seconds or never terminate. Zeebe durably suspends the instance without holding a distributed lock or database connection (ADR-0013). A one-minute timer provides an upper bound: if no match occurs, the order is rejected and the user is notified.

*Transactional outbox for reliable publication.* The approval path uses two sequential workers. `approveOrderWorker` writes both the `APPROVED` status and an outbox row in a single local database transaction. `publishOrderApprovedWorker` then reads and publishes the outbox entry to Kafka. A scheduled safety net republishes any rows that remain unpublished after a crash (ADR-0014). This guarantees that an approved order does not silently miss the event that must later update the portfolio.

*Human escalation for deterministic failures.* If the approval or publication step encounters a deterministic, non-retryable failure (e.g., a missing transaction record or outbox row), the worker throws a typed BPMN error. An interrupting boundary event routes the instance to an operations user task in Camunda Tasklist, where the operator sees the full order context and must document the resolution before closing the task (ADR-0018). This keeps the instance open and auditable instead of retrying indefinitely or failing silently.

*Eventual portfolio propagation.* The portfolio update is deliberately not part of the orchestrated flow. After the outbox event is published to Kafka, `portfolio-service` consumes `OrderApprovedEvent` independently and updates holdings in its own ACID boundary, protected by an idempotent consumer guard (ADR-0016). The executed email confirms the order approval — the business event — not the portfolio propagation, which is a downstream consequence accepted as eventually consistent (ADR-0015).

== Software Architectural Parts

This section covers the software-level decisions that support the event-driven and process-oriented architecture above. These patterns were already familiar from prior coursework (ASSE) and are therefore treated concisely.

=== Microservice Decomposition

CryptoFlow is implemented as five independently deployable Spring Boot 3.5 services on Java 21. Each service maps to one bounded context and communicates exclusively through Kafka and Zeebe. REST endpoints are exposed only for external client access, not for inter-service calls (ADR-0001).

=== Hexagonal Architecture

All five services follow the same internal structure separating the business core from technical adapters:

- `domain/` contains the domain model and invariants.
- `application/` contains use-case logic and the ports that the core depends on.
- `adapter/in/` contains inbound adapters: REST controllers, Kafka listeners, Camunda job workers, or the Binance WebSocket entry.
- `adapter/out/` contains outbound adapters: JPA repositories, Kafka producers, and external clients.

This separation ensures that transport, workflow-engine, and persistence details remain replaceable without moving domain rules into framework code.

=== Data Ownership and Persistence

Each stateful service owns a dedicated PostgreSQL 16 database (ADR-0019): `user-service` owns `user_service_db`, `portfolio-service` owns `portfolio_service_db`, and `transaction-service` owns `transaction_service_db`. No service reads from or writes to another service's tables. Cross-service references use opaque identifiers, not foreign keys.

Schema changes are managed through Flyway versioned migrations. Hibernate runs in `validate` mode. This means that it verifies the entity-to-schema mapping at startup but never modifies the database (ADR-0007). Cross-service consistency is achieved through the patterns described above: Kafka events, replicated read-models, the transactional outbox, and orchestrated sagas.

=== Shared Event Contracts

Event schemas are defined once in the `shared-events` Maven module (ADR-0005). All producing and consuming services depend on it at compile time, ensuring type-safe event contracts. The module contains only Java records and Jackson serialization dependencies  but no business logic. Schema changes are atomic: a single commit updates the contract and all affected consumers.

== Key Architectural Decisions

The repository contains twenty formal Architectural Decision Records (ADRs) in `docs/adrs`. The most significant decisions are:

- *ADR-0001*: Kafka as the sole inter-service communication channel — no synchronous REST between services.
- *ADR-0002*: Event-Carried State Transfer for price data, enabling the portfolio service to answer queries without calling the market data service.
- *ADR-0008*: Camunda 8 (Zeebe) for process orchestration, chosen for its partitioned log, stateless worker model, and connector templates that keep Kafka and SMTP integration inside the BPMN model.
- *ADR-0010*: A dedicated onboarding service as saga orchestrator, separating the cross-context coordination concern from the participating services.
- *ADR-0011*: Event-carried compensation via Kafka for cross-service rollback, maintaining loose coupling even during failure handling.
- *ADR-0012*: Flag-driven completion for Camunda workers, ensuring BPMN compensation branches are always reachable.
- *ADR-0013*: Fairy Tale Saga for the placeOrder workflow, accepting eventual cross-service consistency to avoid distributed locks over a non-deterministic wait.
- *ADR-0014*: Transactional Outbox for reliable publication of approved-order events, preventing silent data loss between database commit and Kafka publication.
- *ADR-0017*: Replicated read-model for autonomous user validation at order placement, avoiding synchronous cross-service calls.
- *ADR-0019*: Database per service for stateful bounded contexts, preserving independent deployment and schema ownership.
- *ADR-0020*: Transaction-service as sole owner of the trading bounded context, keeping order execution concerns isolated from user and portfolio management.
