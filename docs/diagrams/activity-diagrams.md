# Activity Diagrams

## 1. Price Polling & Publishing Workflow (market-data-service)

```mermaid
flowchart TD
    A([Scheduler fires every 10s]) --> B[Call BinanceApiClient.fetchPrices]
    B --> C{API response?}

    C -->|Success| D[Receive JSON array of prices]
    C -->|Error / Timeout| E{Retry count < 3?}

    E -->|Yes| F[Wait exponential backoff]
    F --> B
    E -->|No| G[Log warning, return empty list]
    G --> H([Skip cycle, wait for next tick])

    D --> I{Response empty?}
    I -->|Yes| H
    I -->|No| J[Filter for configured symbols]

    J --> K["Loop: for each symbol"]
    K --> L["PriceEventMapper.map(symbol, price)<br/>→ CryptoPriceUpdatedEvent(UUID, symbol, price, now)"]
    L --> M["KafkaProducer.send(key=symbol, value=event)"]
    M --> N{Kafka ack?}

    N -->|Success| O[Log: Published event for SYMBOL → partition P offset O]
    N -->|Failure| P[Log error, event lost for this cycle]

    O --> Q{More symbols?}
    P --> Q
    Q -->|Yes| K
    Q -->|No| H

    style A fill:#e3f2fd,stroke:#1565c0
    style H fill:#e3f2fd,stroke:#1565c0
    style G fill:#ffebee,stroke:#c62828
    style P fill:#ffebee,stroke:#c62828
    style O fill:#e8f5e9,stroke:#2e7d32
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
