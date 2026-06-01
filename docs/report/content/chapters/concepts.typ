= Lecture Concepts <lecture-concepts>

This chapter connects the main EDPO lecture concepts to the CryptoFlow implementation. The first section keeps the process-oriented material from the first half of the course: Kafka as integration backbone, orchestration, service boundaries, sagas, compensation, outbox, idempotency, read models, and human intervention. The second section extends the same mapping to the event-driven and stream-processing concepts from the second half of the course.

== Process-oriented Concepts

=== Event-Driven Communication through Apache Kafka

Lecture 1 introduced Kafka as the technical backbone for distributed event streams, and Lecture 2 framed event-driven systems as communication through published facts instead of remote commands. CryptoFlow adopts this as its default integration style. @adr-0001 defines Kafka as the sole inter-service communication channel for domain behavior, which means that the services do not call each other synchronously through REST or RPC.

In practice, `market-data-service` publishes `CryptoPriceUpdatedEvent` records to `crypto.price.raw`, Market Scout publishes ask-side liquidity streams for trading, reference-data services publish compacted FX and metadata streams, `user-service` publishes confirmed-user and display-currency events, `transaction-service` publishes approved-order events for portfolio propagation, and the onboarding rollback path uses dedicated compensation topics. @adr-0003 standardizes JSON for the original raw topics, @adr-0032 introduces Avro with Schema Registry for new cross-service derived events, @adr-0004 preserves per-symbol ordering through the Kafka key, and @adr-0005 keeps shared event contracts in the `shared-events` module.

=== Event-Carried State Transfer

Lecture 2 presented Event-Carried State Transfer (ECST), amongst others, as the pattern in which an event carries enough state for consumers to maintain their own local view instead of querying the source service. CryptoFlow applies ECST in the core domain flows and extends it in the second half with compacted reference-data topics.

First, @adr-0002 replicates market prices from `market-data-service` into the `portfolio-service` price cache, so portfolio valuation reads the locally maintained state instead of calling the producer. Second, @adr-0015 keeps portfolio updates autonomous: after an order is approved, `transaction-service` publishes `OrderApprovedEvent`, and `portfolio-service` updates holdings independently. Third, @adr-0011 uses event-carried compensation requests so user and portfolio data can be deleted across service boundaries without synchronous rollback calls. Fourth, @adr-0017 uses the same principle for user validation: `transaction-service` maintains a local confirmed-user projection from `UserConfirmedEvent` messages and validates new orders locally. The second-half extension applies the same cache-as-topic idea to FX rates, coin metadata, display currency, and portfolio values through compacted topics.

Display Currency is the clearest second-half ECST example. `user-service` owns the user's ISO-4217 display preference, persists it with a default of `USD`, exposes `PATCH /users/{id}/display-currency`, and publishes `UserDisplayCurrencyUpdated` to the compacted `user.display-currency` topic (@adr-0028). `portfolio-service` and `transaction-service` consume that topic into local caches. Portfolio converts holdings at API read time from its USDT price and FX caches, while Transaction uses the same local display-currency, FX, and price state for the buy-time quote widget and stores the display price shown at order placement. No dashboard or order path needs a synchronous call back to `user-service` or `fx-rate-service`.

=== Process Orchestration with Camunda 8 with Zeebe

Lectures 3 and 4 introduced workflow engines, BPMN, durable waiting states, and message correlation. CryptoFlow implements these ideas with Camunda 8 / Zeebe, as formalized in @adr-0008.

The alternative would have been Camunda 7 (Operaton), which embeds the engine inside the application and stores process state in the application database. For CryptoFlow this is a poor fit for two reasons. First, `placeOrder` instances wait at an event-based gateway for a price match correlated by `transactionId`. With many concurrent open offers, an embedded engine would require a shared polling table or in-memory workaround, whereas Zeebe's partitioned log lets each instance wait independently without job-lock contention. Second, the onboarding and order-notification workflows use Kafka consumers and SMTP delivery. In Camunda 8, these steps are handled through connector templates directly inside the BPMN model, so the application code contains no notification client or additional Kafka producer for orchestration concerns. With an embedded engine, each integration would need separate application-level client code.

Two BPMN processes are central. `onboarding-service` deploys `userOnboarding.bpmn`, which coordinates user preparation, email confirmation, timeout handling, and the post-confirmation creation steps. `transaction-service` deploys `placeOrder.bpmn`, which coordinates order submission, the wait for `transaction.order-matched`, timeout handling, and the final notification path. In both cases, Zeebe owns the process state, timers, and correlation logic, while the services participate through stateless job workers. This keeps the application databases free of workflow state and allows long-running waits without blocking threads or database transactions. Camunda Operate provides runtime visibility into all in-flight and completed instances, which is especially useful for debugging stuck or rejected orders.

=== Service Autonomy through Bounded Contexts

Lecture 4 emphasized that workflow ownership must not collapse service boundaries into a process monolith. CryptoFlow applies this through explicit bounded contexts and a database-per-service model.

The system is split into Market Data, Reference Data, Portfolio, Trading, User Identity, and Onboarding areas, implemented by nine deployable Spring Boot services. @adr-0019 establishes one database per stateful service, while @adr-0007 and @adr-0020 specify the ownership of the portfolio and trading contexts in detail. Cross-service references are opaque identifiers rather than foreign keys or shared tables, and services depend on Kafka events or local projections rather than direct SQL access.

The most important architectural consequence is @adr-0010: onboarding orchestration moved into a dedicated `onboarding-service`. This keeps the cross-context registration flow in one explicit process owner while preserving the autonomy of `user-service` and `portfolio-service`, each of which still owns its own data and local transaction boundary.

=== Saga Patterns

Lecture 5 introduced multiple transactional saga variants. CryptoFlow implements two different orchestrated saga styles because onboarding and order execution have different coupling and consistency requirements.

==== Parallel Saga

@adr-0010 explains the decisions for the implementation of the onboarding service (`userOnboarding.bpmn`) as a Parallel Saga. After the confirmation message arrives, `userOnboarding.bpmn` reaches a parallel gateway and starts `userCreationWorker` in `user-service` and `portfolioCreationWorker` in `portfolio-service` concurrently. Each worker performs only its own local transaction in its own bounded context. The saga proceeds only if both branches report success. Otherwise the flow moves into compensation for both branches. See @compensation-mechanisms for full detail. 

This fits the lecture pattern well: communication between participants is asynchronous, consistency is eventual, and coordination remains centralized in one orchestrator. CryptoFlow chose this style because onboarding spans multiple services, includes a e-mail confirmation wait, and must remain visible as one end-to-end process.

==== Fairy Tale Saga

@adr-0013 explains the decisions for the implementation of the place order process (`placeOrder.bpmn`) as a Fairy Tale Saga. The process keeps synchronous service-task interactions inside the trading context, but it accepts eventual consistency at the boundary to the portfolio context. Zeebe can wait at the event-based gateway for either a stream-produced order match or a timeout without holding a distributed lock or an open database transaction.

Once the order is approved in `transaction-service`, that trading decision is terminal in its bounded context. The downstream portfolio update is deliberately not folded into the same atomic step. Instead, the order is approved locally and then propagated asynchronously, which is exactly the trade-off of the Fairy Tale Saga used in the lecture.

=== Compensation Mechanisms <compensation-mechanisms>

Compensation is required in CryptoFlow where the business invariant is all-or-nothing: after onboarding, the system should not keep only a user or only a portfolio. @adr-0011 therefore models rollback as explicit forward recovery rather than as a distributed transaction.

If one onboarding branch succeeds and the other fails, the BPMN process routes to compensation handlers that delete the already created entity and publish a compensation request for the peer service. `UserCompensationRequestedEvent` and `PortfolioCompensationRequestedEvent` carry the data needed for the remote delete, and the receiving services treat the delete operation idempotently so at-least-once delivery remains safe. @adr-0012 complements this design: `userCreationWorker` and `portfolioCreationWorker` always complete their Zeebe jobs and report the outcome via `isUserCreated` and `isPortfolioCreated`, ensuring that the BPMN gateways can always reach the modeled compensation paths.

=== Transactional Outbox

Lecture 5 discussed the need to solve inconsistent dual writes. CryptoFlow addresses this with the Transactional Outbox pattern in @adr-0014.

When an order is approved, `approveOrderWorker` stores both the `APPROVED` status and an outbox row in the same local database transaction of `transaction-service`. `publishOrderApprovedWorker` then publishes the pending outbox entry to Kafka and marks it as published. If the service crashes after the database commit but before publication, the scheduler republishes stale unpublished rows. This guarantees that an approved order does not silently miss the event that must later update the portfolio.

=== Idempotent Consumer

Lecture 5 also stressed that retries and redelivery are safe only if consumers are idempotent. CryptoFlow implements this in @adr-0016 for `portfolio-service`.

Before applying an `OrderApprovedEvent`, the service inserts the `transactionId` into the `processed_transaction` table under a unique constraint. If the insert succeeds, the holding update is executed in the same transaction. If the insert violates the constraint, the event has already been processed and is ignored. This protects the portfolio from duplicated Kafka deliveries after crashes, restarts, or rebalancing.

=== Replicated Read-Model

The lecture material on read models and CQRS motivated a local projection for autonomous validation. CryptoFlow applies that idea in @adr-0017.

`transaction-service` keeps its own table of confirmed users instead of calling `user-service` during order placement. `user-service` publishes `UserConfirmedEvent` records to a log-compacted topic, and `transaction-service` upserts the confirmation state into its local database. Order validation is therefore a local read. This is a focused, pragmatic use of a replicated read-model: the write model remains in `user-service`, while the trading context keeps only the projection it needs.

=== Human Intervention as a Stateful Resilience Pattern

Lecture 5 presented human intervention as a stateful resilience pattern for deterministic failures that should not be retried forever. CryptoFlow uses exactly this pattern in @adr-0018 for the `placeOrder` workflow.

If the approval step cannot find the expected transaction record, or if the publication step cannot find the expected outbox row, the worker throws a typed BPMN error. Boundary events route the instance to an operations user task in Camunda Tasklist, where the relevant order context is visible and the operator must document the resolution. This keeps the process instance auditable and operationally visible instead of turning a known data-integrity problem into endless retries or a silent failure.

After the operator resolves the task, the process re-enters the happy path instead of terminating (@adr-0035). The routing is asymmetric to match the two failure cases. An approval failure loops back to the approve step, so the atomic approve-with-outbox write runs again once the missing record is restored. A publication failure instead skips forward to the executed-email step, because the approved-order event has already been published and the resulting portfolio update is choreographed downstream rather than modeled inside the process. At that point there is nothing left for the workflow to revert; the process only transmits the remaining notification, and the unresolved outbox bookkeeping is left as an audit note for a human operations member to reconcile out of band. If an operator closes the task without addressing the cause, the same boundary error fires again and the task reappears, so the escalation is self-healing rather than silently terminal.

== Event-driven Concepts

=== Streams as Unbounded, Replayable Event Logs

The second half of the lectures treated an event stream as an unbounded and replayable sequence of facts. This extends the earlier Kafka integration model: Kafka is no longer only a transport between services, but also the durable input for long-running computations.

CryptoFlow implements this by keeping raw input topics as replay boundaries. Binance ticker events are published to `crypto.price.raw` according to the existing market-data decision in @adr-0006. Binance partial book depth events are published to `crypto.scout.raw` according to @adr-0021. These raw topics let derived topologies rebuild their outputs after a fresh Kafka Streams `application.id`, an offset reset, or a local state-store deletion. @adr-0024 makes this explicit for Market Scout after the service split.

=== Stateless Stream Processing

The lectures introduced single-event stream transformations such as filter, translator, splitter, and router. These operations do not depend on previous events, so they scale horizontally and replay deterministically.

CryptoFlow uses this pattern in the Market Scout ingestion path. `market-partial-book-ingestion-service` captures raw partial book depth records, while `market-order-scout-service` filters out records without asks, splits ask levels into `AskQuote` records, translates quotes into the shared `MatchableAsk` contract, and filters threshold hits into `AskOpportunity` records. @adr-0023 separates raw ingestion from scout processing, @adr-0022 defines the scout-local Avro contracts, and @adr-0026 defines `MatchableAsk` as the cross-service ask contract for transaction matching.

The same stateless shape appears in Reference Data. `fx-rate-service` polls a provider, filters the supported currency pairs, translates them into `FxRate` events, and publishes them to the compacted `reference.fx.rate` topic as described in @adr-0029. `coin-metadata-service` does the same for slow-moving cryptocurrency metadata, publishing `CoinMetadata` records to `reference.crypto.metadata` as described in @adr-0033.

=== Stream-Table Duality and Local State

The lectures then introduced stream-table duality: a `KStream` represents facts over time, while a `KTable` represents the latest state obtained by applying those facts. Kafka Streams materializes those tables in local state stores backed by changelog topics.

CryptoFlow uses this in portfolio valuation. @adr-0034 places a Kafka Streams topology inside `portfolio-service`: approved orders are folded into a holdings table keyed by `userId|symbol`, prices are materialized by symbol, and the resulting position values are grouped into a per-user `portfolio-value-store`. The endpoint `GET /portfolios/{userId}/streams-value` reads that local store through interactive queries instead of issuing a synchronous request to another service.

Transaction matching also depends on local state. @adr-0027 replaces heap-based ticker matching with persistent stores for pending bids, matched transaction ids, and allocated ask quote ids. This makes the matching decision restartable and replayable. A transaction that already matched is skipped on replay, and an ask quote can be allocated to at most one pending bid.

=== Event Time, Windows, Grace Periods, and Suppression

The windowing lectures distinguished event time from processing time and introduced grace periods for bounded late events. CryptoFlow applies event time wherever the business meaning depends on when the market event happened.

Market Scout aggregates `AskOpportunity` events into window summaries. The topology groups opportunities by symbol, applies a configured tumbling window, and emits `ScoutWindowSummary` records. This is part of the scout-local Avro event model from @adr-0022.

The OHLC topology is the more complete windowing implementation. @adr-0031 decides that OHLC bars are emitted venue-native in USDT on `crypto.ohlc.1m`, `crypto.ohlc.5m`, and `crypto.ohlc.1h`. The topology extracts event timestamps from price events, aggregates open/high/low/close values in tumbling event-time windows, applies a grace period, and uses `suppress(untilWindowCloses)` so downstream consumers receive one final closed candle rather than every intermediate update.

Transaction matching uses event-time validity as business logic rather than as a DSL windowed join. @adr-0027 defines a 30-second bid validity interval plus a five-second processing and retention margin aligned with the Camunda timeout. A `MatchableAsk` can match a `BuyBid` only if the ask's event time falls inside the 30-second business interval and price/quantity constraints pass.

=== Joins and Repartitioning

The second-half lectures covered joins between streams and tables, plus the repartitioning needed when a topology changes keys. CryptoFlow implements these concepts in multiple places.

The FX localisation design in @adr-0030 uses a stream-table join: `crypto.price.clean` is joined with the compacted `reference.fx.rate` table to produce `LocalizedPrice` events. This is an ADR-locked target design; the currently implemented valuation and OHLC topologies still read `crypto.price.raw`. The implemented OHLC flow uses the same pattern family for metadata enrichment. @adr-0033 materializes `reference.crypto.metadata` as a `GlobalKTable` and left-joins it into closed OHLC bars so dashboard consumers receive names, logo URLs, base/quote assets, and ranking data without synchronous metadata lookups.

Portfolio valuation demonstrates table-table joining and multiphase repartitioning. @adr-0034 joins the holdings table with the latest price table by symbol. The intermediate result is keyed by `userId|symbol`, which is correct for per-position values. The dashboard needs a per-user sum, so the topology groups by `userId`, triggering the repartition step that moves all positions for one user to the same task before aggregating into `portfolio-value-store`.

=== Event Contracts and Schema Evolution

The stream-processing lectures also emphasized that derived streams need explicit contracts. CryptoFlow therefore uses different serialization strategies depending on ownership and coupling.

Raw replay topics remain JSON, following @adr-0003 and the raw-boundary decision in @adr-0022. This keeps `crypto.price.raw` and `crypto.scout.raw` easy to inspect and replay during demonstrations.

Scout-local derived topics use registryless Avro. `AskQuote`, `AskOpportunity`, and `ScoutWindowSummary` are owned by `market-order-scout-service`, so @adr-0022 keeps them as local generated Avro classes without adding Schema Registry infrastructure. `MatchableAsk` is a deliberate boundary case: @adr-0026 places it in `shared-events` because it crosses into the Trading bounded context, but the shipped implementation still serializes it with the local registryless `SpecificAvroSerde` rather than Confluent Schema Registry.

New cross-service derived contracts use Confluent Schema Registry. @adr-0032 introduces registry-backed Avro for events such as `FxRate`, `LocalizedPrice`, `PortfolioValue`, `Ohlc`, `CoinMetadata`, and `UserDisplayCurrencyUpdated`. In the shipped slice, `FxRate`, `PortfolioValue`, `Ohlc`, `CoinMetadata`, and `UserDisplayCurrencyUpdated` are active registry-backed contracts, while `LocalizedPrice` remains the schema-managed target for ADR-0030. This gives independently deployable producers and consumers a central compatibility boundary while preserving JSON at raw replay points.
