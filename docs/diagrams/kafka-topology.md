# Kafka Topic Topology

## Topic Overview

```mermaid
graph LR
    subgraph Producers
        MDS["market-data-service"]
        PS_P["portfolio-service"]
        TS["trading-service<br/>(post-MVP)"]
    end

    subgraph Topics
        CPR["crypto.price.raw<br/>──────────────<br/>Partitions: 3<br/>Retention: 1h<br/>Key: symbol"]
        CPE["crypto.price.enriched<br/>──────────────<br/>Partitions: 3<br/>Retention: 6h<br/>Key: symbol<br/>(post-MVP)"]
        PT["portfolio.transactions<br/>──────────────<br/>Partitions: 3<br/>Retention: 7d<br/>Key: userId<br/>(post-MVP)"]
        PA["portfolio.alerts<br/>──────────────<br/>Partitions: 1<br/>Retention: 24h<br/>(post-MVP)"]
        DLT["crypto.price.raw.DLT<br/>──────────────<br/>Partitions: 1<br/>Retention: 7d<br/>(Dead Letter)"]
    end

    subgraph Consumers
        PS_C["portfolio-service<br/>group: portfolio-service-group"]
        NS["notification-service<br/>(post-MVP)"]
        TS_C["trading-service<br/>(post-MVP)"]
    end

    MDS -->|produce| CPR
    PS_P -.->|produce| PA
    TS -.->|produce| PT

    CPR -->|consume| PS_C
    CPR -.->|consume| TS_C
    CPR -.->|consume| NS
    PA -.->|consume| NS
    PT -.->|consume| PS_C
    CPR -->|error recovery| DLT

    style CPR fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style DLT fill:#ffebee,stroke:#c62828,stroke-width:2px
    style CPE fill:#fff3e0,stroke:#ef6c00,stroke-dasharray: 5 5
    style PT fill:#fff3e0,stroke:#ef6c00,stroke-dasharray: 5 5
    style PA fill:#fff3e0,stroke:#ef6c00,stroke-dasharray: 5 5
```

## Partition Key Strategy

```mermaid
graph TD
    subgraph "market-data-service publishes with key = symbol"
        E1["CryptoPriceUpdatedEvent<br/>key: BTCUSDT"]
        E2["CryptoPriceUpdatedEvent<br/>key: ETHUSDT"]
        E3["CryptoPriceUpdatedEvent<br/>key: SOLUSDT"]
        E4["CryptoPriceUpdatedEvent<br/>key: BNBUSDT"]
        E5["CryptoPriceUpdatedEvent<br/>key: XRPUSDT"]
    end

    subgraph "crypto.price.raw (3 partitions)"
        P0["Partition 0"]
        P1["Partition 1"]
        P2["Partition 2"]
    end

    E1 -->|"hash(BTCUSDT) % 3"| P1
    E2 -->|"hash(ETHUSDT) % 3"| P0
    E3 -->|"hash(SOLUSDT) % 3"| P2
    E4 -->|"hash(BNBUSDT) % 3"| P0
    E5 -->|"hash(XRPUSDT) % 3"| P1

    subgraph "Guarantee"
        G["All events for one symbol always<br/>go to the same partition<br/>→ per-symbol ordering preserved"]
    end

    style G fill:#e8f5e9,stroke:#2e7d32
```

> **Note:** The actual partition assignment depends on the Murmur2 hash of the key. The partition numbers above are illustrative.

## Topic Configuration Summary

| Topic | Partitions | Retention | Key | Producers | Consumers | Status |
|-------|-----------|-----------|-----|-----------|-----------|--------|
| `crypto.price.raw` | 3 | 1 h | symbol | market-data-service | portfolio-service | **MVP** |
| `crypto.price.raw.DLT` | 1 | 7 d | (original key) | DefaultErrorHandler | Ops (manual) | **MVP** |
| `crypto.price.enriched` | 3 | 6 h | symbol | — | — | Post-MVP |
| `portfolio.transactions` | 3 | 7 d | userId | trading-service | portfolio-service | Post-MVP |
| `portfolio.alerts` | 1 | 24 h | — | portfolio-service | notification-service | Post-MVP |
