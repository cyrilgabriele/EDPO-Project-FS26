= Lecture Concepts <lecture-concepts>

This chapter follows the sequence in which the relevant concepts appeared in the EDPO lectures: Kafka and event-driven communication in Lecture 1 and 2, process orchestration and service boundaries in Lecture 3 and 4, and transactional saga and resilience patterns in Lecture 5. For each concept listed in @domain-and-goals, it explains briefly and precisely how CryptoFlow applies it and which ADRs capture the underlying decision.

== Event-Driven Communication through Apache Kafka

Lecture 1 introduced Kafka as the technical backbone for distributed event streams, and Lecture 2 framed event-driven systems as communication through published facts instead of remote commands. CryptoFlow adopts this as its default integration style. ADR-0001 defines Kafka as the sole inter-service communication channel for domain behavior, which means that the services do not call each other synchronously through REST or RPC.

In practice, `market-data-service` publishes `CryptoPriceUpdatedEvent` records to `crypto.price.raw`, `user-service` publishes `UserConfirmedEvent` records for downstream consumers, `transaction-service` publishes approved-order events for portfolio propagation, and the onboarding rollback path uses dedicated compensation topics. ADR-0003 standardizes JSON serialization for all Kafka messages, ADR-0004 preserves per-symbol ordering through the Kafka key, and ADR-0005 keeps all event contracts in the shared `shared-events` module.

== Event-Carried State Transfer

Lecture 2 presented Event-Carried State Transfer (ECST), amongst others, as the pattern in which an event carries enough state for consumers to maintain their own local view instead of querying the source service. CryptoFlow applies ECST in four places.

First, ADR-0002 replicates market prices from `market-data-service` into the `portfolio-service` price cache, so portfolio valuation reads the locally maintained state instead of calling the producer. Second, ADR-0015 keeps portfolio updates autonomous: after an order is approved, `transaction-service` publishes `OrderApprovedEvent`, and `portfolio-service` updates holdings independently. Third, ADR-0011 uses event-carried compensation requests so user and portfolio data can be deleted across service boundaries without synchronous rollback calls. Fourth, ADR-0017 uses the same principle for user validation: `transaction-service` maintains a local confirmed-user projection from `UserConfirmedEvent` messages and validates new orders locally.

== Process Orchestration with Camunda 8 with Zeebe

Lectures 3 and 4 introduced workflow engines, BPMN, durable waiting states, and message correlation. CryptoFlow implements these ideas with Camunda 8 / Zeebe, as formalized in ADR-0008.

The alternative would have been Camunda 7 (Operaton), which embeds the engine inside the application and stores process state in the application database. For CryptoFlow this is a poor fit for two reasons. First, `placeOrder` instances wait at an event-based gateway for a price match correlated by `transactionId`. With many concurrent open offers, an embedded engine would require a shared polling table or in-memory workaround, whereas Zeebe's partitioned log lets each instance wait independently without job-lock contention. Second, the onboarding and order-notification workflows use Kafka consumers and SMTP delivery. In Camunda 8, these steps are handled through connector templates directly inside the BPMN model, so the application code contains no notification client or additional Kafka producer for orchestration concerns. With an embedded engine, each integration would need separate application-level client code.

Two BPMN processes are central. `onboarding-service` deploys `userOnboarding.bpmn`, which coordinates user preparation, email confirmation, timeout handling, and the post-confirmation creation steps. `transaction-service` deploys `placeOrder.bpmn`, which coordinates order submission, price-match waiting, timeout handling, and the final notification path. In both cases, Zeebe owns the process state, timers, and correlation logic, while the services participate through stateless job workers. This keeps the application databases free of workflow state and allows long-running waits without blocking threads or database transactions. Camunda Operate provides runtime visibility into all in-flight and completed instances, which is especially useful for debugging stuck or rejected orders.

== Service Autonomy through Bounded Contexts

Lecture 4 emphasized that workflow ownership must not collapse service boundaries into a process monolith. CryptoFlow applies this through explicit bounded contexts and a database-per-service model.

The system is split into five contexts: Market-Data, Portfolio, Trading, User, and Onboarding. ADR-0019 establishes one database per stateful service, while ADR-0007 and ADR-0020 specify the ownership of the portfolio and trading contexts in detail. Cross-service references are opaque identifiers rather than foreign keys or shared tables, and services depend on Kafka events or local projections rather than direct SQL access.

The most important architectural consequence is ADR-0010: onboarding orchestration moved into a dedicated `onboarding-service`. This keeps the cross-context registration flow in one explicit process owner while preserving the autonomy of `user-service` and `portfolio-service`, each of which still owns its own data and local transaction boundary.

== Saga Patterns

Lecture 5 introduced multiple transactional saga variants. CryptoFlow implements two different orchestrated saga styles because onboarding and order execution have different coupling and consistency requirements.

=== Parallel Saga

ADR-0010 explains the decisions for the implementation of the onboarding service (`userOnboarding.bpmn`) as a Parallel Saga. After the confirmation message arrives, `userOnboarding.bpmn` reaches a parallel gateway and starts `userCreationWorker` in `user-service` and `portfolioCreationWorker` in `portfolio-service` concurrently. Each worker performs only its own local transaction in its own bounded context. The saga proceeds only if both branches report success. Otherwise the flow moves into compensation for both branches. See @compensation-mechanisms for full detail. 

This fits the lecture pattern well: communication between participants is asynchronous, consistency is eventual, and coordination remains centralized in one orchestrator. CryptoFlow chose this style because onboarding spans multiple services, includes a e-mail confirmation wait, and must remain visible as one end-to-end process.

=== Fairy Tale Saga

ADR-0013 explains the decisions for the implementation of the place order process (`placeOrder.bpmn`) as a Fairy Tale Saga. The process keeps synchronous service-task interactions inside the trading context, but it accepts eventual consistency at the boundary to the portfolio context. Zeebe can wait at the event-based gateway for either a price match or a timeout without holding a distributed lock or an open database transaction.

Once the order is approved in `transaction-service`, that trading decision is terminal in its bounded context. The downstream portfolio update is deliberately not folded into the same atomic step. Instead, the order is approved locally and then propagated asynchronously, which is exactly the trade-off of the Fairy Tale Saga used in the lecture.

== Compensation Mechanisms <compensation-mechanisms>

Compensation is required in CryptoFlow where the business invariant is all-or-nothing: after onboarding, the system should not keep only a user or only a portfolio. ADR-0011 therefore models rollback as explicit forward recovery rather than as a distributed transaction.

If one onboarding branch succeeds and the other fails, the BPMN process routes to compensation handlers that delete the already created entity and publish a compensation request for the peer service. `UserCompensationRequestedEvent` and `PortfolioCompensationRequestedEvent` carry the data needed for the remote delete, and the receiving services treat the delete operation idempotently so at-least-once delivery remains safe. ADR-0012 complements this design: `userCreationWorker` and `portfolioCreationWorker` always complete their Zeebe jobs and report the outcome via `isUserCreated` and `isPortfolioCreated`, ensuring that the BPMN gateways can always reach the modeled compensation paths.

== Transactional Outbox

Lecture 5 discussed the need to solve inconsistent dual writes. CryptoFlow addresses this with the Transactional Outbox pattern in ADR-0014.

When an order is approved, `approveOrderWorker` stores both the `APPROVED` status and an outbox row in the same local database transaction of `transaction-service`. `publishOrderApprovedWorker` then publishes the pending outbox entry to Kafka and marks it as published. If the service crashes after the database commit but before publication, the scheduler republishes stale unpublished rows. This guarantees that an approved order does not silently miss the event that must later update the portfolio.

== Idempotent Consumer

Lecture 5 also stressed that retries and redelivery are safe only if consumers are idempotent. CryptoFlow implements this in ADR-0016 for `portfolio-service`.

Before applying an `OrderApprovedEvent`, the service inserts the `transactionId` into the `processed_transaction` table under a unique constraint. If the insert succeeds, the holding update is executed in the same transaction. If the insert violates the constraint, the event has already been processed and is ignored. This protects the portfolio from duplicated Kafka deliveries after crashes, restarts, or rebalancing.

== Replicated Read-Model

The lecture material on read models and CQRS motivated a local projection for autonomous validation. CryptoFlow applies that idea in ADR-0017.

`transaction-service` keeps its own table of confirmed users instead of calling `user-service` during order placement. `user-service` publishes `UserConfirmedEvent` records to a log-compacted topic, and `transaction-service` upserts the confirmation state into its local database. Order validation is therefore a local read. This is a focused, pragmatic use of a replicated read-model: the write model remains in `user-service`, while the trading context keeps only the projection it needs.

== Human Intervention as a Stateful Resilience Pattern

Lecture 5 presented human intervention as a stateful resilience pattern for deterministic failures that should not be retried forever. CryptoFlow uses exactly this pattern in ADR-0018 for the `placeOrder` workflow.

If the approval step cannot find the expected transaction record, or if the publication step cannot find the expected outbox row, the worker throws a typed BPMN error. Boundary events route the instance to an operations user task in Camunda Tasklist, where the relevant order context is visible and the operator must document the resolution. This keeps the process instance open, auditable, and operationally visible instead of turning a known data-integrity problem into endless retries or a silent failure.
