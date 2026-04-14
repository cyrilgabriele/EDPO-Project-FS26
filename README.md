# CryptoFlow

> Course: Event-driven and Process-oriented Architectures (EDPO), FS2026
>
> Copyright 2026 - present [Cyril Gabriele](mailto:cyril.gabriele@student.unisg.ch), [Ioannis Theodosiadis](mailto:ioannis.theodosiadis@student.unisg.ch), University of St. Gallen

CryptoFlow is a multi-service crypto portfolio simulation platform built with Apache Kafka, Spring Boot, PostgreSQL, and Camunda 8. It demonstrates event-driven architecture patterns including event-carried state transfer, process orchestration, sagas with compensation, and the outbox pattern.

## Services

| Module | Port | Responsibility |
| --- | ---: | --- |
| `shared-events` | — | Shared Kafka event records (Maven dependency) |
| `market-data-service` | `8081` | Subscribes to Binance WebSocket streams, publishes `crypto.price.raw` |
| `portfolio-service` | `8082` | Maintains a local price cache, stores holdings, exposes read APIs |
| `transaction-service` | `8083` | Runs the place-order BPMN, matches orders, publishes `transaction.order.approved` |
| `user-service` | `8084` | Stores users and confirmation links, handles onboarding compensation |
| `onboarding-service` | `8085` | Deploys `userOnboarding.bpmn` to Camunda 8 |

## Deploying the stack

### Prerequisites

| Tool | Version |
| --- | --- |
| Java | 21 |
| Maven | 3.9+ |
| Docker / Docker Compose | any recent version |
| Camunda 8 SaaS | required for onboarding and order workflows |

### 1. Create your `.env` file

The compose stack reads Camunda credentials and other secrets from `docker/.env`. Copy the example and fill in your values:

```bash
cp docker/.env.example docker/.env
# fill in the CAMUNDA_* values for each service
```

The example file documents every variable. The four Camunda-connected services (`portfolio-service`, `transaction-service`, `user-service`, `onboarding-service`) each need their own client ID, secret, cluster ID, and region.

### 2. Start the stack

```bash
cd docker
docker compose up -d --build
```

This starts all services and the supporting infrastructure:

| Service | URL |
| --- | --- |
| Kafka broker | `localhost:9092` |
| Kafka UI | `http://localhost:8080` |
| PostgreSQL | `localhost:5432` |
| pgAdmin | `http://localhost:5050` |
| market-data-service | `http://localhost:8081` |
| portfolio-service | `http://localhost:8082` |
| transaction-service | `http://localhost:8083` |
| user-service | `http://localhost:8084` |
| onboarding-service | `http://localhost:8085` |

Three per-service databases (`user_service_db`, `portfolio_service_db`, `transaction_service_db`) are created automatically on first startup.

## Repository layout

```text
EDPO-Project-FS26/
├── shared-events/          # shared Kafka event records
├── market-data-service/
├── portfolio-service/
├── transaction-service/
├── user-service/
├── onboarding-service/
├── docker/                 # Docker Compose stack, .env.example, DB init scripts
├── assignments/
│   ├── ex-1/               # Kafka producer/consumer experiments (plain Java)
│   ├── ex-2/               # Spring Kafka implementation report
│   ├── ex-3/               # BPMN workflow descriptions and diagrams
│   └── ex-4/               # Architecture decision records (PDF)
└── docs/
    ├── adrs/               # All ADRs as individual Markdown files
    ├── diagrams/           # Context map and sequence diagrams
    ├── presentation/       # Course presentation deck
    └── report/             # Final project report
```

## Experiments and assignments

| Assignment | Location | Contents |
| --- | --- | --- |
| Exercise 1 — Kafka fundamentals | `assignments/ex-1/` | Producer/consumer experiments with plain Java; fault-tolerance and reliability scenarios; findings consolidated in `experiments.md` |
| Exercise 2 — Spring Kafka | `assignments/ex-2/` | Implementation report covering the market-data and portfolio services |
| Exercise 3 — BPMN workflows | `assignments/ex-3/` | Workflow descriptions (`workflows.md`) and BPMN diagram exports for the onboarding and place-order sagas |
| Exercise 4 — Architecture decisions | `assignments/ex-4/` | ADR compilation as PDF |

## Report and documentation

| Resource | Location |
| --- | --- |
| Final report | `docs/report/` |
| Architecture decision records | `docs/adrs/` |
