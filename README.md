# CryptoFlow - Event-driven Crypto Portfolio Platform

> Course: Event-driven and Process-oriented Architectures (EDPO), FS2026
>
> Copyright 2026 - present [Cyril Gabriele](mailto:cyril.gabriele@student.unisg.ch), [Ioannis Theodosiadis](mailto:ioannis.theodosiadis@student.unisg.ch), University of St. Gallen

## What is CryptoFlow?

CryptoFlow is a multi-service crypto portfolio simulation platform built around Apache Kafka, Spring Boot, PostgreSQL, and Camunda 8.

This branch is no longer just the original market-data/portfolio demo. The current system includes:

- live market-data ingestion from Binance
- a portfolio read model backed by event-carried state transfer
- a user-onboarding workflow with confirmation and compensation
- an order workflow with price matching, timeout handling, and Kafka publication through an outbox
- shared event contracts in a Maven monorepo

## Current modules

| Module | Port | Responsibility |
|---|---:|---|
| `shared-events` | - | Shared Kafka event records used across services |
| `market-data-service` | `8081` | Consumes Binance ticker streams and publishes `crypto.price.raw` |
| `portfolio-service` | `8082` | Maintains the local price cache, exposes read APIs, creates/deletes portfolios for onboarding, consumes approved orders |
| `transaction-service` | `8083` | Deploys `placeOrder.bpmn`, validates and matches orders, stores transaction state, publishes `transaction.order.approved` |
| `user-service` | `8084` | Stores users and confirmation links, exposes `GET /user/confirm/{userId}`, publishes `user.confirmed`, handles compensation |
| `onboarding-service` | `8085` | Deploys `userOnboarding.bpmn` to Camunda 8 |

## Architecture at a glance

See the current system diagram in [`docs/diagrams/context-map.md`](docs/diagrams/context-map.md).

## Prerequisites

| Tool | Version |
|---|---|
| Java | 21 |
| Maven | 3.9+ |
| Docker / Docker Compose | any recent version |
| Camunda 8 | required for the onboarding and order workflows |

The workflow-aware services expect service-specific Camunda environment variables. Check these files for the exact variable names:

- `onboarding-service/src/main/resources/application.yml`
- `portfolio-service/src/main/resources/application.yml`
- `transaction-service/src/main/resources/application.yaml`
- `user-service/src/main/resources/application.yml`

The onboarding BPMN currently uses a Camunda email connector. To run that flow unchanged, the referenced SMTP secret must exist in your Camunda environment, or the BPMN connector configuration must be adapted.

## Getting started

### Option A - Docker stack for Kafka, Postgres, and the containerized services

```bash
cd docker
docker compose up -d --build
docker compose ps
```

After exporting the required Camunda variables for the workflow-aware services, this starts:

- Kafka in KRaft mode on `localhost:9092` (no ZooKeeper in this branch)
- Kafka UI on `http://localhost:8080`
- PostgreSQL on `localhost:5432`
- pgAdmin on `http://localhost:5050`
- `market-data-service` on `http://localhost:8081`
- `portfolio-service` on `http://localhost:8082`
- `transaction-service` on `http://localhost:8083`
- `user-service` on `http://localhost:8084`

The compose stack creates three per-service databases on first startup:

- `user_service_db`
- `portfolio_service_db`
- `transaction_service_db`

`onboarding-service` is present in this branch but is not part of `docker/docker-compose.yml`, so run it locally when you want the onboarding workflow deployed:

```bash
mvn spring-boot:run -pl onboarding-service
```

### Option B - Infrastructure in Docker, services locally

Start the local infrastructure:

```bash
cd docker
docker compose up -d kafka kafka-ui postgres pgadmin
```

Then, from the repository root, start the services you need.

`market-data-service` works with its local defaults:

```bash
mvn spring-boot:run -pl market-data-service
```

`portfolio-service` needs the Camunda variables in your shell plus Kafka pointed at the host broker when run outside Docker:

```bash
KAFKA_BOOTSTRAP_SERVERS=localhost:9092 \
mvn spring-boot:run -pl portfolio-service
```

`transaction-service` needs Camunda variables in your shell plus the local Postgres/Kafka endpoints:

```bash
KAFKA_BOOTSTRAP_SERVERS=localhost:9092 \
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/transaction_service_db \
mvn spring-boot:run -pl transaction-service
```

`user-service` needs Camunda variables in your shell plus host-local database and confirmation URL settings:

```bash
KAFKA_BOOTSTRAP_SERVERS=localhost:9092 \
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/user_service_db \
USER_CONFIRMATION_BASE_URL=http://localhost:8084 \
mvn spring-boot:run -pl user-service
```

`onboarding-service` only deploys the onboarding BPMN, so it just needs the Camunda variables:

```bash
mvn spring-boot:run -pl onboarding-service
```

## Current workflows

### 1. User onboarding saga

- `onboarding-service` deploys `userOnboarding.bpmn`.
- Camunda starts the process and sends a job to `user-service` to prepare a confirmation link.
- `user-service` stores the pending link and exposes confirmation through `GET /user/confirm/{userId}`.
- When the link is opened, `user-service` both correlates `UserConfirmedEvent` back to Camunda and publishes `user.confirmed` to Kafka.
- Camunda then runs user creation and portfolio creation in parallel through `user-service` and `portfolio-service`.
- If one branch fails, compensation is requested asynchronously through `crypto.portfolio.compensation` or `crypto.user.compensation`.

### 2. Place-order saga

- `transaction-service` deploys `placeOrder.bpmn`.
- A Camunda form collects `userId`, `symbol`, `amount`, and target `price`.
- `transaction-service` validates the order against its local replicated read model of confirmed users, fed by the compacted `user.confirmed` topic.
- Incoming `crypto.price.raw` events are matched against in-memory pending orders.
- On a price match, `transaction-service` approves the order, stores an outbox row, and publishes `transaction.order.approved`.
- `portfolio-service` consumes `transaction.order.approved` and idempotently upserts the holding, updating weighted-average purchase price where needed.
- If no match arrives before the BPMN timer expires, the order is rejected.
- A scheduled recovery job republishes orphaned unpublished outbox rows older than five minutes.

### 3. Read-side portfolio queries

- `portfolio-service` consumes `crypto.price.raw` and maintains a local `LocalPriceCache`.
- Portfolio valuation reads never call `market-data-service` synchronously.
- `GET /portfolios/{userId}/value` returns `503` until all required prices are present in the local cache.

## Kafka topics in use

| Topic | Producer | Consumer(s) | Notes |
|---|---|---|---|
| `crypto.price.raw` | `market-data-service` | `portfolio-service`, `transaction-service` | 3 partitions, live Binance price updates |
| `crypto.price.raw.DLT` | dead-letter handling for price events | none in this branch | 1 partition |
| `user.confirmed` | `user-service` | `transaction-service` | compacted topic for the confirmed-user read model |
| `transaction.order.approved` | `transaction-service` | `portfolio-service` | 3 partitions |
| `crypto.portfolio.compensation` | `user-service` | `portfolio-service` | onboarding rollback from user side |
| `crypto.user.compensation` | `portfolio-service` | `user-service` | onboarding rollback from portfolio side |

## HTTP surfaces and local tools

| Surface | URL / endpoint | Purpose |
|---|---|---|
| Kafka UI | `http://localhost:8080` | Inspect topics and messages |
| pgAdmin | `http://localhost:5050` | Inspect PostgreSQL databases |
| market-data dashboard | `http://localhost:8081/` | Static demo page for the producer side |
| market-data API | `http://localhost:8081/api/dashboard` | Recent published events and configured symbols |
| portfolio dashboard | `http://localhost:8082/` | Static demo page for the consumer/read-model side |
| portfolio API | `http://localhost:8082/api/dashboard` | Current price-cache snapshot |
| price API | `GET http://localhost:8082/prices` | Full local price cache |
| single price API | `GET http://localhost:8082/prices/{symbol}` | Latest cached price for one symbol |
| portfolio API | `GET http://localhost:8082/portfolios/{userId}` | Holdings for a user |
| valuation API | `GET http://localhost:8082/portfolios/{userId}/value` | Total portfolio value in USDT |
| user confirmation API | `GET http://localhost:8084/user/confirm/{userId}` | Completes onboarding confirmation |

`transaction-service` and `onboarding-service` do not expose a public REST API in this branch; they participate through Camunda workers and BPMN deployment.

## Repository layout

```text
EDPO-Project-FS26/
├── pom.xml
├── shared-events/
├── market-data-service/
├── portfolio-service/
├── transaction-service/
├── user-service/
├── onboarding-service/
├── docker/
└── docs/
```

## Useful documentation

- [`assignments/ex-3/workflows.md`](assignments/ex-3/workflows.md) - BPMN workflow rationale and flow descriptions
- [`docs/diagrams/context-map.md`](docs/diagrams/context-map.md) - bounded-context and system overview diagrams
- [`docs/diagrams/sequence-event-flow.md`](docs/diagrams/sequence-event-flow.md) - onboarding, trading, and read-path sequence diagrams
- [`docs/adrs/`](docs/adrs/) - architecture decision records

## Team

| Name | Contribution |
|---|---|
| Ioannis Theodosiadis | Architecture and implementation |
| Cyril Gabriele | Architecture and implementation |
