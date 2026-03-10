# Context Map – Bounded Contexts

## Overview

```mermaid
graph TB
    subgraph External
        BinanceAPI["Binance WebSocket API<br/>(External System)"]
    end

    subgraph CryptoFlow Platform
        MD["Market Data Context<br/>─────────────────<br/>Owns: price ticks, symbol catalogue,<br/>stream subscriptions<br/>─────────────────<br/>Produces:<br/>CryptoPriceUpdatedEvent"]
        PM["Portfolio Management Context<br/>─────────────────<br/>Owns: holdings, local price cache,<br/>portfolio snapshots<br/>─────────────────<br/>Consumes:<br/>CryptoPriceUpdatedEvent<br/>Produces:<br/>PortfolioValueUpdatedEvent"]
        TR["Trading Context<br/>─────────────────<br/>Owns: order state, trade history<br/>─────────────────<br/>Consumes:<br/>CryptoPriceUpdatedEvent<br/>Produces:<br/>OrderPlacedEvent,<br/>OrderExecutedEvent,<br/>OrderFailedEvent"]
        NT["Notification Context<br/>─────────────────<br/>Owns: alert rules,<br/>delivery status<br/>─────────────────<br/>Consumes:<br/>CryptoPriceUpdatedEvent,<br/>PortfolioValueUpdatedEvent<br/>Produces:<br/>NotificationSentEvent"]
        UI["User & Identity Context<br/>─────────────────<br/>Owns: credentials, profiles,<br/>session tokens"]
    end

    BinanceAPI -- "Conformist<br/>(we adapt to their stream format)" --> MD
    MD -- "Published Language<br/>(shared-events module)<br/>Upstream → Downstream" --> PM
    MD -- "Published Language<br/>Upstream → Downstream" --> TR
    MD -- "Published Language<br/>Upstream → Downstream" --> NT
    PM -- "Published Language<br/>Upstream → Downstream" --> NT
    TR -- "Published Language<br/>Upstream → Downstream" --> PM
    UI -. "Identity propagation<br/>(userId in events)" .-> PM
    UI -. "Identity propagation" .-> TR
```

## Upstream / Downstream Summary

| Upstream | Downstream | Integration Pattern |
|----------|------------|---------------------|
| Binance WebSocket API | Market Data Context | WebSocket stream subscription, we adapt to their message format |
| Market Data Context | Portfolio Management Context | `shared-events` module, Kafka topic `crypto.price.raw` |
| Market Data Context | Trading Context | Kafka topic `crypto.price.raw` |
| Market Data Context | Notification Context | Kafka topic `crypto.price.raw` |
| Portfolio Management Context | Notification Context | Kafka topic (portfolio value events) |
| Trading Context | Portfolio Management Context | Kafka topic `portfolio.transactions` |
| User & Identity Context | Portfolio / Trading | `userId` propagated in event payloads |
