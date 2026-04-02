# Kafka Topic Topology

## Overview

```mermaid
graph LR
    MDS["market-data-service"]
    TS["transaction-service"]
    PS["portfolio-service"]
    US["user-service"]

    CPR["crypto.price.raw"]
    TOD["transaction.order.approved"]
    UCR["user.confirmed<br/>(compacted user-read-model)"]
    CPC["crypto.portfolio.compensation"]
    CUC["crypto.user.compensation"]
    DLT["crypto.price.raw.DLT"]

    MDS -->|publishes| CPR
    CPR -->|consumes| TS
    CPR -->|consumes| PS

    TS -->|publishes| TOD
    TOD -->|consumes| PS

    US -->|publishes| UCR
    UCR -->|consumes| TS

    US -->|publishes| CPC
    CPC -->|consumes| PS

    PS -->|publishes| CUC
    CUC -->|consumes| US

    CPR -->|failed records after retries| DLT

    style CPR fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style TOD fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    style UCR fill:#fff8e1,stroke:#ef6c00,stroke-width:2px
    style CPC fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
    style CUC fill:#ede7f6,stroke:#4527a0,stroke-width:2px
    style DLT fill:#ffebee,stroke:#c62828,stroke-width:2px
```

## Rendered Preview

![Rendered Kafka topology](./kafka-topology-render.svg)

## Topic Summary

| Topic | Producer | Consumer | Notes |
|-------|----------|----------|-------|
| `crypto.price.raw` | `market-data-service` | `portfolio-service`, `transaction-service` | Shared live price stream |
| `transaction.order.approved` | `transaction-service` | `portfolio-service` | Approved order events |
| `user.confirmed` | `user-service` | `transaction-service` | Compacted user-read-model topic |
| `crypto.portfolio.compensation` | `user-service` | `portfolio-service` | Compensation flow |
| `crypto.user.compensation` | `portfolio-service` | `user-service` | Compensation flow |
| `crypto.price.raw.DLT` | Consumer error handler | Operational review | Dead-letter topic for failed `crypto.price.raw` records after retries |
