# Sequence Diagram - Event Flow

These diagrams separate Kafka topic traffic from Camunda message correlation. Kafka UI shows the
Kafka arrows; Camunda Operate shows the workflow message arrows.

## 1. Onboarding: Confirmation, Read Model, Compensation

```mermaid
sequenceDiagram
    participant User
    participant C as Camunda<br/>userOnboarding
    participant U as user-service
    participant KU as Kafka<br/>user.confirmed
    participant T as transaction-service
    participant P as portfolio-service
    participant KC as Kafka<br/>compensation topics

    User->>C: submit onboarding form
    C->>U: prepare confirmation link
    U-->>User: send confirmation email
    User->>U: click confirmation link
    U->>C: correlate `UserConfirmedEvent`
    U->>KU: publish `user.confirmed`
    KU-->>T: upsert confirmed-user read model
    Note over T: later order validation can run locally

    par Parallel creation
        C->>U: create user
        U-->>C: user created or failed
    and
        C->>P: create portfolio
        P-->>C: portfolio created or failed
    end

    alt Both tasks succeed
        Note over C: onboarding completes successfully
    else User creation fails after portfolio exists
        C->>U: run user compensation
        U->>KC: publish `crypto.portfolio.compensation`
        KC-->>P: delete portfolio
        Note over C: onboarding ends as compensated / failed
    else Portfolio creation fails after user exists
        C->>P: run portfolio compensation
        P->>KC: publish `crypto.user.compensation`
        KC-->>U: delete user
        Note over C: onboarding ends as compensated / failed
    end
```

## 2. Trading: Price Match, Outbox, Portfolio Update

```mermaid
sequenceDiagram
    participant User
    participant C as Camunda<br/>placeOrder
    participant T as transaction-service
    participant R as transaction-service<br/>confirmed-user read model
    participant M as market-data-service
    participant K as Kafka
    participant O as transaction-service<br/>outbox table
    participant P as portfolio-service

    User->>C: submit order form
    C->>T: run `placeOrderWorker`
    T->>R: validate `userId`
    R-->>T: confirmed user exists
    T->>T: persist pending order and register matcher

    M->>K: publish `crypto.price.raw`
    K-->>T: deliver price event
    T->>T: match price against pending orders

    alt Order matches target price
        T->>C: correlate `priceMatchedEvent`
        C->>T: run `approveOrderWorker`
        T->>O: persist APPROVED state + unpublished outbox row
        C->>T: run `publishOrderApprovedWorker`
        T->>K: publish `transaction.order.approved`
        T->>O: mark outbox row published
        K-->>P: consume approved order
        P->>P: upsert holding
        C-->>User: send execution email
    else No match before timeout
        C-->>User: send rejection email
    end
```

## 3. Operational Side Paths

### 3.1 Outbox Recovery

```mermaid
sequenceDiagram
    participant O as transaction-service<br/>outbox table
    participant S as transaction-service<br/>OutboxScheduler
    participant K as Kafka<br/>transaction.order.approved
    participant P as portfolio-service

    Note over O: Row exists with `publishedAt = null`
    S->>O: scan rows older than 5 minutes
    O-->>S: orphaned outbox row
    S->>K: publish `transaction.order.approved`
    S->>O: mark row published
    K-->>P: consume approved order
```

### 3.2 Price Event Dead-Letter Flow

```mermaid
sequenceDiagram
    participant M as market-data-service
    participant K as Kafka<br/>crypto.price.raw
    participant C as price consumer
    participant D as Kafka<br/>crypto.price.raw.DLT

    M->>K: publish `CryptoPriceUpdatedEvent`
    K-->>C: deliver record

    alt Deserialization succeeds
        C->>C: process event normally
    else Deserialization still fails after retries
        C->>D: publish failed record to DLT
        Note over D: inspect in Kafka UI for debugging
    end
```

## 4. Portfolio Read Path: Valuation from Local Price Cache

```mermaid
sequenceDiagram
    participant Client
    participant API as portfolio-service<br/>REST API
    participant DB as portfolio store
    participant Cache as local price cache

    Client->>API: GET /portfolios/{userId}/value
    API->>DB: load portfolio and holdings
    API->>Cache: read latest cached prices

    alt All holding prices are cached
        API-->>Client: total portfolio value
    else One or more prices missing
        API-->>Client: 503 Service Unavailable
        Note over API,Cache: portfolio-service does not call market-data-service synchronously
    end
```
