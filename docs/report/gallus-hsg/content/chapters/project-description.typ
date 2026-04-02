= Project Description <project-description>

CryptoFlow is a crypto portfolio simulation platform that demonstrates event-driven and process-oriented architecture patterns in a distributed microservice environment. The system allows users to register, manage cryptocurrency portfolios, and place simulated trading orders. This, all coordinated through asynchronous event streams and orchestrated business processes.

== Domain and Goals

The central goal of this project was to implement the concepts covered in the EDPO lectures in a self-chosen project. For that purpose, CryptoFlow was designed as a high-level cryptocurrency platform in which users can register, observe live market prices, manage simulated portfolios, and place simulated trading orders. The platform is intentionally not a production exchange; it serves as a concrete case study for applying the architectural and integration concepts from the course in one coherent end-to-end system.

The concepts implemented in CryptoFlow are:
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

At a high level, CryptoFlow consists of five Spring Boot microservices, Apache Kafka for asynchronous communication, PostgreSQL for persistent service-owned state, Camunda 8 (Zeebe) for workflow orchestration, and Binance as the external market-data source.

Each service owns a bounded context: market-data ingestion, portfolio management, trading, user identity, or onboarding orchestration. Kafka transports the domain events between these contexts, while Zeebe coordinates the long-running onboarding and order-placement workflows without introducing direct service-to-service calls.

From the outside, the platform is defined by two main end-to-end flows. The onboarding flow creates a confirmed user together with a matching portfolio, and the trading flow matches pending orders against live market prices before propagating approved trades to the portfolio context. @architecture provides the detailed service-by-service architecture, event topology, and BPMN interaction model.

== Technology Stack

The technology choices reflect the course curriculum and the requirements of a distributed event-driven system:

- *Java 21* and *Spring Boot 3.5* provide the service runtime, dependency injection, and web layer.
- *Apache Kafka* (Confluent 7.6, KRaft mode) serves as the sole inter-service communication channel for domain events, with topics explicitly created and managed via Spring `@Bean` definitions.
- *Camunda 8 / Zeebe* (SaaS) orchestrates multi-step business processes through BPMN models, with services acting as stateless job workers connected via gRPC.
- *PostgreSQL 16* with *Flyway* migrations stores persistent data for the portfolio and user bounded contexts. Hibernate runs in `validate` mode only.
- *Docker Compose* provisions the full local infrastructure stack (Kafka, PostgreSQL, Kafka UI, pgAdmin) alongside all five application services.
- The *Binance WebSocket API* provides real-time cryptocurrency price feeds at no cost and without authentication.

All services share event definitions through a `shared-events` Maven module, ensuring compile-time consistency of event schemas across the entire system.
