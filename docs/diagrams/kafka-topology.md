# Kafka Topic Topology

## Topic Overview

```mermaid
graph LR
    subgraph Producers
        MDS["market-data-service"]
    end

    subgraph Topics
        CPR["crypto.price.raw<br/>──────────────<br/>Partitions: 3<br/>Retention: 1h<br/>Key: symbol"]
        DLT["crypto.price.raw.DLT<br/>──────────────<br/>Partitions: 1<br/>Retention: 7d<br/>(Dead Letter)"]
    end

    subgraph Consumers
        PS_C["portfolio-service<br/>group: portfolio-service-group"]
    end

    MDS -->|produce| CPR
    CPR -->|consume| PS_C
    CPR -->|error recovery| DLT

    style CPR fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style DLT fill:#ffebee,stroke:#c62828,stroke-width:2px
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
        E6["CryptoPriceUpdatedEvent<br/>key: LTCUSDT"]
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
    E6 -->|"hash(LTCUSDT) % 3"| P2

    subgraph "Guarantee"
        G["All events for one symbol always<br/>go to the same partition<br/>→ per-symbol ordering preserved"]
    end

    style G fill:#e8f5e9,stroke:#2e7d32
```

## Topic Configuration Summary

| Topic | Partitions | Retention | Key | Producers | Consumers |
|-------|-----------|-----------|-----|-----------|-----------|
| `crypto.price.raw` | 3 | 1 h | symbol | market-data-service | portfolio-service |
| `crypto.price.raw.DLT` | 1 | 7 d | (original key) | DefaultErrorHandler | Ops (manual) |
