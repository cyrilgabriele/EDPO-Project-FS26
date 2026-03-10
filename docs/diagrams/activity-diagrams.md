# Activity Diagrams

## 1. WebSocket Stream & Publishing Workflow (market-data-service)

```mermaid
flowchart TD
    A([Application starts]) --> B[Open WebSocket to Binance]
    B --> C[Subscribe to configured symbol streams]
    C --> D{Connection established?}

    D -->|No| E{Max reconnect attempts?}
    E -->|No| F[Wait exponential backoff]
    F --> B
    E -->|Yes| G[Log critical error, enter retry loop]
    G --> H([Wait longer backoff, retry from start])
    H --> B

    D -->|Yes| I([Listening: await next ticker message])

    I --> J[Receive ticker update from Binance]
    J --> K["PriceEventMapper.map(symbol, price)<br/>→ CryptoPriceUpdatedEvent(UUID, symbol, price, now)"]
    K --> L["KafkaProducer.send(key=symbol, value=event)"]
    L --> M{Kafka ack?}

    M -->|Success| N[Log: Published event for SYMBOL → partition P offset O]
    M -->|Failure| O[Log error, event lost]

    N --> I
    O --> I

    I --> P{Connection dropped?}
    P -->|Yes| Q[Log warning: WebSocket disconnected]
    Q --> B

    style A fill:#e3f2fd,stroke:#1565c0
    style I fill:#e3f2fd,stroke:#1565c0
    style G fill:#ffebee,stroke:#c62828
    style O fill:#ffebee,stroke:#c62828
    style N fill:#e8f5e9,stroke:#2e7d32
```

## 2. Event Consumption & Error Handling Workflow (portfolio-service)

```mermaid
flowchart TD
    A([Kafka delivers message batch]) --> B[Deserialise message]
    B --> C{Deserialisation OK?}

    C -->|No| D{Retry count < N?}
    D -->|Yes| E[Retry deserialisation]
    E --> C
    D -->|No| F[DeadLetterPublishingRecoverer<br/>→ publish to crypto.price.raw.DLT]
    F --> G[Log: Poison pill sent to DLT]
    G --> M

    C -->|Yes| H[Extract CryptoPriceUpdatedEvent]
    H --> I{eventId already processed?<br/>Idempotency check}

    I -->|Yes, duplicate| J[Skip event, log duplicate]
    J --> M

    I -->|No, new event| K[LocalPriceCache.update<br/>symbol → price]
    K --> L[Record eventId as processed]

    L --> M{More messages in batch?}
    M -->|Yes| B
    M -->|No| N[Commit offsets to Kafka]
    N --> O([Wait for next poll])

    style A fill:#e3f2fd,stroke:#1565c0
    style O fill:#e3f2fd,stroke:#1565c0
    style F fill:#ffebee,stroke:#c62828
    style G fill:#ffebee,stroke:#c62828
    style J fill:#fff3e0,stroke:#ef6c00
    style K fill:#e8f5e9,stroke:#2e7d32
```

## 3. Portfolio Valuation Query Workflow (portfolio-service REST)

```mermaid
flowchart TD
    A([Client: GET /portfolios/userId/value]) --> B[PortfolioController receives request]
    B --> C[PortfolioService.getPortfolioValue]
    C --> D[Load holdings from PostgreSQL via JPA]
    D --> E{Holdings found?}

    E -->|No| F[Return 404 Not Found]
    E -->|Yes| G[For each holding: read price from LocalPriceCache]

    G --> H{All prices available in cache?}
    H -->|No| I[Return 503: price data not yet available]
    H -->|Yes| J["Calculate: sum(holding.qty × cachedPrice)"]

    J --> K[Return 200 with total portfolio value]

    style A fill:#e3f2fd,stroke:#1565c0
    style F fill:#ffebee,stroke:#c62828
    style I fill:#fff3e0,stroke:#ef6c00
    style K fill:#e8f5e9,stroke:#2e7d32
```
