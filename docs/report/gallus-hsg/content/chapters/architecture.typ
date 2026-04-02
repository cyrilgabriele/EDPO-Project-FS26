= Architecture <architecture>

This chapter describes the system architecture of CryptoFlow, covering the service topology, Kafka event flows, BPMN process models, and pointers to the architectural decision records that motivated the design.

== Service Topology

CryptoFlow is a distributed system comprising five Spring Boot microservices that communicate exclusively through Apache Kafka events and Camunda 8 (Zeebe) process orchestration. No service makes synchronous REST or gRPC calls to another service for domain operations — REST endpoints are exposed only for external client access.

#figure(
  image("figures/context-map.png", width: 100%),
  caption: [Platform-level service topology showing the five services, event contracts, external actors, and Camunda orchestration],
) <fig:system-overview>

@fig:system-overview gives the detailed runtime view that expands the brief overview from  @project-description. It highlights the five deployable services, the shared event-contract module, the external Binance feed, and the two orchestration entry points that interact with Camunda.

The services and their roles are:

/ Market Data Service (8081): Inbound adapter to the Binance WebSocket API. Subscribes to real-time ticker streams for six cryptocurrency pairs and publishes `CryptoPriceUpdatedEvent` records to Kafka. The service is stateless and does not own a database.

/ Portfolio Service (8082): Maintains portfolio and holding state in PostgreSQL and keeps a local in-memory price cache derived from `crypto.price.raw`. It exposes REST endpoints for valuation queries, updates holdings from approved-order events, and acts as a Camunda job worker for portfolio creation during onboarding.

/ Transaction Service (8083): Owns the trading bounded context. It deploys the `placeOrder.bpmn` process, validates incoming orders against a replicated read model of confirmed users, matches pending orders against live prices, and publishes approved-order events for downstream portfolio updates.

/ User Service (8084): Owns user accounts, confirmation links, and confirmation-state changes. It acts as a Camunda job worker for user preparation, creation, and invalidation during onboarding, publishes confirmed-user events for downstream consumers, and handles compensation by deleting users when the onboarding saga fails.

/ Onboarding Service (8085): Dedicated saga orchestrator that deploys `userOnboarding.bpmn` to Zeebe and coordinates the registration flow across the user and portfolio contexts. It owns no persistent business data because the workflow state itself lives in the Zeebe engine.

The `shared-events` module shown in @fig:system-overview is not a runtime service. It is a shared Maven module that defines the Kafka event contracts consumed and produced by the participating services, ensuring compile-time consistency across the codebase.

Supporting infrastructure includes a Kafka broker (KRaft mode), PostgreSQL 16, Kafka UI for monitoring, and pgAdmin for database administration, all provisioned via Docker Compose.

== Kafka Topology

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

@tab:kafka-topics captures the topic-level configuration, while @tab:kafka-producers-consumers shows which service publishes and consumes each stream. The onboarding service is intentionally absent because the current implementation coordinates via Zeebe rather than Kafka. Except for the compacted `user.confirmed` topic, all current topics inherit the broker's 1-hour development retention from Docker Compose. The partition key strategy is topic-specific: `crypto.price.raw` uses the trading symbol (e.g., `BTCUSDT`) with the deterministic `symbolIndex % (modulo) numPartitions` mapping from ADR-0004; `transaction.order.approved` uses `transactionId`; `user.confirmed` and both compensation topics use `userId`; and the DLT preserves the failed record's original Kafka key.

== BPMN Process Flows

=== User Onboarding Process

The `userOnboarding.bpmn` process, deployed by the onboarding service, orchestrates user registration as a parallel saga:

+ A user task collects credentials (username, password, email).
+ The `prepareUserWorker` generates a UUID `userId`, creates a confirmation link (status: PENDING), and builds the confirmation email content.
+ A Camunda email connector sends the confirmation email via SMTP.
+ An event-based gateway waits for either:
  - A `Message_UserConfirmed` message, correlated by `userConfirmationLinkId`, indicating the user clicked the confirmation link; or
  - A 1-minute timer expiration, after which the `invalidateConfirmationWorker` marks the link as INVALIDATED and the process ends.
+ Upon confirmation, a parallel gateway splits execution:
  - `userCreationWorker` creates the user record in PostgreSQL.
  - `portfolioCreationWorker` creates a portfolio record in PostgreSQL.
+ Both workers always complete successfully, communicating outcomes through boolean flags (`isUserCreated`, `isPortfolioCreated`).
+ Exclusive gateways inspect the flags. If either is `false`, compensation events trigger deletion of the sibling entity.
+ If both are `true`, the parallel paths join and the process completes successfully.

#figure(
  image("figures/userOnboarding-bpmn.png", width: 100%),
  caption: [User onboarding BPMN process with parallel saga, confirmation wait, and compensation paths],
) <fig:onboarding-parallel-saga>

@fig:onboarding-parallel-saga visualizes the event-based confirmation wait, the parallel split into user and portfolio creation, and the modeled compensation branches for partial failure.

=== Place Order Process

The `placeOrder.bpmn` process, deployed by the transaction service, handles order execution:

+ A user task collects order details (symbol, amount, target price).
+ The `order-processing-worker` creates a pending order and begins matching against live prices.
+ An event-based gateway waits for either:
  - A `price-matched` message, correlated by `transactionId`, indicating a market price matched the order; or
  - A 1-minute timeout.
+ The outcome (execution or rejection) triggers an email notification to the user.

#figure(
  image("figures/placeOrder-bpmn.png", width: 100%),
  caption: [Place order BPMN process with price matching, timeout handling, and downstream publication],
) <fig:placeorder-fairy-tale-saga>

Figure @fig:placeorder-fairy-tale-saga shows the event-based wait for either a price match or timeout, the approval path inside the trading context, and the subsequent notification and publication steps.

== Hexagonal Architecture

Because of ASSE we trated the Hexagonal architecture as given and therefore it is not treated here as one of the explicit lecture concepts. Nevertheless, it is the internal structural pattern used consistently across the services and therefore belongs in the architecture chapter.

All five services separate the business core from technical adapters:
- `domain/` contains the domain model and invariants.
- `application/` contains use-case logic and the ports that the core depends on.
- `adapter/in/` contains inbound technical entry points such as REST controllers, Kafka listeners, Camunda job workers, or the Binance WebSocket entry.
- `adapter/out/` contains outbound integrations such as JPA repositories, Kafka producers, and external clients.

This separation is visible across the codebase. In `portfolio-service`, `PortfolioController` and `PriceEventConsumer` are inbound adapters, while persistence and compensation publishing sit on the outbound side; the valuation logic itself stays in the application and domain layers. `transaction-service` follows the same pattern for BPMN workers, price consumers, outbox publication, and persistence. `user-service` applies it to the confirmation endpoint, onboarding workers, repositories, and compensation producers. The result is that transport, workflow-engine, and persistence details remain replaceable without moving domain rules into framework code.

== Key Design Decisions

The repository currently contains twenty formal Architectural Decision Records (ADRs) in `docs/adrs`. The most significant decisions include:

- *ADR-0001*: Kafka as the sole inter-service communication channel — no synchronous REST between services.
- *ADR-0002*: Event-Carried State Transfer for price data, enabling the portfolio service to answer queries without calling the market data service.
- *ADR-0008*: Camunda 8 (Zeebe) for process orchestration, chosen for its partitioned log, stateless worker model, and managed SaaS deployment.
- *ADR-0010*: A dedicated onboarding service as saga orchestrator, separating the cross-context coordination concern from the participating services.
- *ADR-0011*: Event-carried compensation via Kafka for cross-service rollback, maintaining loose coupling even during failure handling.
- *ADR-0012*: Flag-driven completion for Camunda workers, ensuring BPMN compensation branches are always reachable.
- *ADR-0019*: Database per service for stateful bounded contexts, preserving independent deployment and schema ownership.
- *ADR-0020*: Transaction-service as sole owner of the trading bounded context, keeping order execution concerns isolated from user and portfolio management.
