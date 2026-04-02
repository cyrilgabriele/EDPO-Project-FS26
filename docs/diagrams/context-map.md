# Context Map

## Bounded Context View

```mermaid
graph TB
    User["End user"]
    Binance["Binance"]
    Camunda["Camunda"]

    subgraph CryptoFlow
        MDC["Market Data Context"]
        UIC["User Identity Context"]
        OBC["Onboarding Context"]
        TRC["Trading Context"]
        PFC["Portfolio Context"]
    end

    User --> OBC
    User --> TRC
    Binance --> MDC

    OBC -.->|"orchestrated in"| Camunda
    TRC -.->|"orchestrated in"| Camunda

    MDC -->|"price events"| TRC
    MDC -->|"price events"| PFC
    UIC -->|"confirmed users"| TRC
    TRC -->|"approved orders"| PFC
    UIC -->|"compensation events"| PFC
    PFC -->|"compensation events"| UIC
```

Notes:

- `Market Data Context` owns market-price ingestion and publication.
- `User Identity Context` owns users, confirmation state, and confirmed-user events.
- `Onboarding Context` coordinates the registration flow across user and portfolio creation.
- `Trading Context` owns pending orders, matching, and order approval.
- `Portfolio Context` owns holdings, valuation, and the local price read model.

## Overview

```mermaid
graph TB
    User["End user"]
    Binance["Binance feeds<br/>(external market source)"]
    Camunda["Camunda orchestration"]

    subgraph Platform
        MD["market-data-service"]
        US["user-service"]
        ONB["onboarding-service<br/>(deploys onboarding BPMN)"]
        TR["transaction-service"]
        PF["portfolio-service"]
        SE["shared-events<br/>(Kafka contracts)"]
    end

    User --> Camunda
    Binance --> MD
    MD -->|"crypto.price.raw"| PF
    MD -->|"crypto.price.raw"| TR

    ONB -.->|"deploys userOnboarding"| Camunda
    TR -.->|"deploys placeOrder"| Camunda
    Camunda -.->|"onboarding jobs"| US
    Camunda -.->|"onboarding jobs"| PF
    Camunda -.->|"order jobs"| TR

    US -->|"user.confirmed (compacted)"| TR
    US -->|"crypto.portfolio.compensation"| PF
    PF -->|"crypto.user.compensation"| US

    TR -->|"transaction.order.approved"| PF

    SE -. shared event contracts .- MD
    SE -. shared event contracts .- US
    SE -. shared event contracts .- TR
    SE -. shared event contracts .- PF
```

## Notes

- `market-data-service` ingests Binance market feeds and publishes price data to both `portfolio-service` and `transaction-service`.
- `user-service` publishes `user.confirmed`; `transaction-service` keeps a local confirmed-user read model from that compacted topic.
- `portfolio-service` consumes both price updates and approved-order events.
- `onboarding-service` deploys the onboarding BPMN, while `transaction-service` deploys and runs the order workflow.
- `Camunda` coordinates the `userOnboarding` and `placeOrder` flows across the participating services.
- Compensation between `user-service` and `portfolio-service` is handled asynchronously through Kafka topics.
