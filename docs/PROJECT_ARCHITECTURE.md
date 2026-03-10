# CryptoFlow – Project Architecture

> **Course:** Event-driven and Process-oriented Architectures (EDPO), FS2026
> **Exercise:** 2 – Kafka with Spring
> **Tech Stack:** Java 21 · Spring Boot 3 · Apache Kafka · Docker · (Camunda – later)

---

## 1. Vision & Scope

**CryptoFlow** is a crypto portfolio simulation and tracking platform. Users can monitor live cryptocurrency prices sourced from the Binance public API, simulate purchases, manage a virtual portfolio, and (in later iterations) define automated trading rules modelled as BPMN processes in Camunda.

The platform is deliberately built as a set of loosely coupled microservices that communicate exclusively via Apache Kafka. This design makes it an ideal vehicle for demonstrating the four core EDA patterns from Lecture 2, as well as Kafka choreography, and later Camunda-based orchestration.

---

## 2. MVP Scope (Exercise 2)

The MVP focuses on the event-streaming backbone:

| Service | Role |
|---|---|
| `market-data-service` | Subscribes to Binance WebSocket streams and **produces** price events to Kafka |
| `portfolio-service` | **Consumes** price events and maintains a local, eventually-consistent price state (ECST) |

These two services are sufficient to demonstrate at least two EDA patterns from Lecture 2 and the Kafka producer/consumer split with Spring Kafka.

---

## 3. Bounded Contexts

Domain-Driven Design identifies the following bounded contexts in the full application. The MVP covers only the first two.

### 3.1 Market Data Context *(MVP)*
**Responsibility:** Acquiring, normalising, and publishing raw market data.
**Owns:** price tick data, symbol catalogue, stream subscriptions.
**Does not own:** portfolio state, user preferences, orders.
**Produces:** `CryptoPriceUpdatedEvent`

### 3.2 Portfolio Management Context *(MVP)*
**Responsibility:** Tracking the composition and current value of a user's virtual portfolio.
**Owns:** portfolio holdings, local price cache, portfolio snapshots.
**Does not own:** live prices (derives them via ECST from the Market Data Context).
**Consumes:** `CryptoPriceUpdatedEvent`
**Produces:** `PortfolioValueUpdatedEvent` *(stretch goal within MVP)*

### 3.3 Trading Context *(Post-MVP)*
**Responsibility:** Accepting and executing simulated buy/sell orders.
**Owns:** order state, trade history.
**Consumes:** `CryptoPriceUpdatedEvent` (to validate orders against current price)
**Produces:** `OrderPlacedEvent`, `OrderExecutedEvent`, `OrderFailedEvent`

### 3.4 Notification Context *(Post-MVP)*
**Responsibility:** Dispatching alerts to users when price or portfolio thresholds are crossed.
**Owns:** alert rules, notification delivery status.
**Consumes:** `CryptoPriceUpdatedEvent`, `PortfolioValueUpdatedEvent`
**Produces:** `NotificationSentEvent`

### 3.5 User & Identity Context *(Post-MVP)*
**Responsibility:** Registration, authentication, and user profile management.
**Owns:** user credentials, profile data, session tokens.

---

## 4. Service Architecture

### 4.1 `market-data-service` (Producer)

```
┌──────────────────────────────────────────────────┐
│                market-data-service               │
│                                                  │
│  ┌──────────────────────────────────────────────┐ │
│  │  BinanceWebSocketClient                     │ │
│  │  (subscribes to Binance ticker streams)     │ │
│  └──────────────────────┬───────────────────── ┘ │
│                                  │               │
│                         ┌────────▼─────────────┐ │
│                         │  PriceEventMapper    │ │
│                         └────────┬─────────────┘ │
│                                  │               │
│                         ┌────────▼─────────────┐ │
│                         │  KafkaProducer       │ │
│                         │  (Spring Kafka)      │ │
│                         └──────────────────────┘ │
└──────────────────────────────────────────────────┘
                              │
                              ▼
                   Topic: crypto.price.raw
```

**Key responsibilities:**
- Subscribes to Binance WebSocket streams (`wss://stream.binance.com:9443/ws/<symbol>@ticker`) for a configurable list of symbols (e.g. `BTCUSDT`, `ETHUSDT`, `SOLUSDT`)
- Receives real-time push ticker updates from Binance
- Maps incoming ticker messages to `CryptoPriceUpdatedEvent` (see Section 6)
- Publishes to Kafka topic `crypto.price.raw` with the symbol as the message key (for partition affinity)
- Handles WebSocket disconnections with automatic reconnection and exponential backoff (see Section 8)

**Spring components:** `WebSocketClient`, `KafkaTemplate<String, CryptoPriceUpdatedEvent>`

### 4.2 `portfolio-service` (Consumer + State)

```
                   Topic: crypto.price.raw
                              │
                              ▼
┌─────────────────────────────────────────────────┐
│                 portfolio-service               │
│                                                 │
│  ┌──────────────────────────────────────────┐   │
│  │  PriceEventConsumer (@KafkaListener)     │   │
│  └─────────────────┬────────────────────────┘   │
│                    │                            │
│          ┌─────────▼──────────┐                 │
│          │  LocalPriceCache   │  ◀── ECST       │
│          │  (in-memory / DB)  │                 │
│          └─────────┬──────────┘                 │
│                    │                            │
│          ┌─────────▼──────────┐                 │
│          │  PortfolioService  │                 │
│          │  (domain logic)    │                 │
│          └─────────┬──────────┘                 │
│                    │                            │
│          ┌─────────▼──────────┐                 │
│          │  REST API          │  ◀── CQRS Query │
│          │  (Spring MVC)      │                 │
│          └────────────────────┘                 │
└─────────────────────────────────────────────────┘
```

**Key responsibilities:**
- Consumes `CryptoPriceUpdatedEvent` from `crypto.price.raw`
- Maintains a **local price cache** per symbol (Event-carried State Transfer pattern)
- Calculates current portfolio value on demand using the local cache – no synchronous call to `market-data-service`
- Exposes REST endpoints for querying portfolio state (CQRS read side)
- (Stretch) Evaluates simple alert rules and publishes `PriceAlertTriggeredEvent` to `portfolio.alerts`

**Spring components:** `@KafkaListener`, `@Service`, `@RestController`, `JpaRepository` (PostgreSQL)

---

## 5. EDA Patterns Applied

### 5.1 Event Notification
**Where:** `market-data-service` → `portfolio-service`
**Description:** The market data service emits a lightweight `CryptoPriceUpdatedEvent` whenever it obtains a new price tick. Downstream consumers (portfolio service, and later the notification service) react to these events autonomously. The producer has no knowledge of, and no dependency on, any consumer. This allows new consumers to be added (e.g. a dedicated alert service) without modifying the producer at all.

**Demonstrated by:** Starting only the producer and observing events flowing into Kafka; then starting the portfolio consumer and observing it reacting without any code change in the producer.

### 5.2 Event-carried State Transfer (ECST)
**Where:** `portfolio-service` local price cache
**Description:** Instead of the portfolio service making a synchronous REST call to `market-data-service` every time it needs the current price to compute portfolio value, it subscribes to `crypto.price.raw` and maintains its own local replica of the latest price per symbol. This eliminates temporal coupling: the portfolio service continues to operate and serve queries even when `market-data-service` is temporarily unavailable.

**Demonstrated by:** Stopping `market-data-service` and showing that `portfolio-service` still returns portfolio valuations using its cached prices.

### 5.3 Event Sourcing *(Post-MVP / Stretch)*
**Where:** `portfolio-service` transaction log
**Description:** All portfolio mutations (asset purchases, sales) are stored as an immutable sequence of events (`AssetPurchasedEvent`, `AssetSoldEvent`). The current portfolio state is derived by replaying these events rather than by storing a mutable snapshot. This provides a full audit trail and enables time-travel queries.

**Demonstrated by:** Replaying the event log from the beginning and reconstructing portfolio state at any point in time.

### 5.4 CQRS (Command Query Responsibility Segregation) *(Post-MVP)*
**Where:** `portfolio-service` and `trading-service`
**Description:** Write operations (place order, update portfolio) flow through the Kafka command side, while read operations (get portfolio, get price history) are served from a dedicated read model that is updated asynchronously from events. This separates scaling concerns for heavy read workloads (e.g. dashboard polling) from write workloads.

---

## 6. Kafka Topics & Event Schemas

### Topics

| Topic | Partitions | Retention | Description |
|---|---|---|---|
| `crypto.price.raw` | 3 | 1 h | Raw price ticks from Binance |
| `crypto.price.enriched` | 3 | 6 h | Enriched events with 24 h change % *(post-MVP)* |
| `portfolio.transactions` | 3 | 7 d | Buy/sell transaction events *(post-MVP)* |
| `portfolio.alerts` | 1 | 24 h | Alert trigger events *(post-MVP)* |
| `crypto.price.raw.DLT` | 1 | 7 d | Dead letter topic for failed price events |

**Partition key strategy:** The Kafka message key is the trading symbol (e.g. `BTCUSDT`). This guarantees that all events for a given symbol land in the same partition, preserving ordering per symbol.

### Event Schemas (Java Records)

```java
// Produced by: market-data-service
// Topic: crypto.price.raw
public record CryptoPriceUpdatedEvent(
    String eventId,          // UUID – used for idempotent processing
    String symbol,           // e.g. "BTCUSDT"
    BigDecimal price,        // current price in USDT
    Instant timestamp        // time of Binance API response
) {}
```

```java
// Produced by: portfolio-service (stretch)
// Topic: portfolio.alerts
public record PriceAlertTriggeredEvent(
    String eventId,
    String userId,
    String symbol,
    BigDecimal triggerPrice,
    String alertType,        // e.g. "PRICE_ABOVE", "PRICE_BELOW"
    Instant timestamp
) {}
```

```java
// Produced by: trading-service (post-MVP)
// Topic: portfolio.transactions
public record AssetPurchasedEvent(
    String eventId,
    String userId,
    String symbol,
    BigDecimal quantity,
    BigDecimal priceAtPurchase,
    Instant timestamp
) {}
```

---

## 7. Infrastructure & Repository Structure

### Repository Layout (Monorepo)

```
cryptoflow/
├── market-data-service/
│   ├── src/main/java/ch/unisg/cryptoflow/marketdata/
│   │   ├── adapter/in/binance/         # Binance WebSocket stream client
│   │   ├── adapter/out/kafka/         # KafkaTemplate producer
│   │   ├── application/               # Use cases (ports & adapters)
│   │   └── domain/                    # PriceTick domain object
│   ├── src/main/resources/
│   │   └── application.yml
│   └── Dockerfile
│
├── portfolio-service/
│   ├── src/main/java/ch/unisg/cryptoflow/portfolio/
│   │   ├── adapter/in/kafka/          # @KafkaListener consumers
│   │   ├── adapter/in/web/            # REST controllers (CQRS read)
│   │   ├── adapter/out/persistence/   # JPA repositories
│   │   ├── application/               # Use cases
│   │   └── domain/                    # Portfolio, PriceCache domain
│   ├── src/main/resources/
│   │   └── application.yml
│   └── Dockerfile
│
├── shared-events/                     # Shared Kafka event DTOs
│   └── src/main/java/ch/unisg/cryptoflow/events/
│       └── CryptoPriceUpdatedEvent.java
│
├── docker/
│   ├── docker-compose.yml             # Full local stack
│   └── docker-compose.kafka.yml       # Kafka + Zookeeper only
│
├── docs/
│   ├── architecture/
│   │   ├── PROJECT_ARCHITECTURE.md    # This document
│   │   ├── bounded-contexts.md
│   │   └── adr/                       # Architecture Decision Records
│   └── api/
│       └── portfolio-service-api.md
│
├── .github/
│   ├── ISSUE_TEMPLATE/
│   └── workflows/
│       └── build.yml                  # CI: build + test all services
│
├── README.md
└── pom.xml                            # Maven parent POM
```

### Docker Compose Services

```yaml
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.6.0

  kafka:
    image: confluentinc/cp-kafka:7.6.0
    ports: ["9092:9092"]

  kafka-ui:
    image: provectuslabs/kafka-ui:latest
    ports: ["8080:8080"]          # Local Kafka monitoring dashboard

  postgres:
    image: postgres:16-alpine
    ports: ["5432:5432"]

  market-data-service:
    build: ./market-data-service
    ports: ["8081:8081"]

  portfolio-service:
    build: ./portfolio-service
    ports: ["8082:8082"]
```

---

## 8. Error Scenarios

These are the error and fault scenarios to be demonstrated in the project report and/or live demo.

### 8.1 Binance WebSocket Disconnection (Producer-side failure)
**Scenario:** The Binance WebSocket stream drops due to a network issue or Binance maintenance.
**Handling:** The `BinanceWebSocketClient` detects the disconnect and automatically reconnects with exponential backoff. During the disconnection window, no events are published to Kafka. Consumers continue serving queries from their cached state (ECST).
**What to demonstrate:** Simulate by blocking the WebSocket endpoint (e.g. via a firewall rule or Docker network disconnect) and observing the reconnection attempts in logs, followed by resumed event flow once connectivity is restored.

### 8.2 Consumer Failure & At-Least-Once Delivery
**Scenario:** The `portfolio-service` crashes while processing a batch of events. Kafka retains the uncommitted offsets.
**Handling:** Spring Kafka defaults to `AckMode.BATCH` – offsets are only committed after the listener method returns successfully. On restart, the consumer replays unprocessed events.
**Risk:** Duplicate processing. Mitigation: idempotent consumer (see 8.3).
**What to demonstrate:** Kill the portfolio-service container mid-batch and observe that on restart it re-processes events without data loss.

### 8.3 Idempotent Consumer (Duplicate Events)
**Scenario:** Network issues cause the producer to publish the same price event twice (Kafka's at-least-once guarantee), or the consumer retries a batch.
**Handling:** Each `CryptoPriceUpdatedEvent` carries a UUID `eventId`. The portfolio service tracks processed event IDs in a short-lived cache (Caffeine or Redis). If an event with an already-seen ID arrives, it is skipped.
**What to demonstrate:** Manually publish a duplicate event to `crypto.price.raw` and show that the local price cache is not double-updated.

### 8.4 Poison Pill / Malformed Message
**Scenario:** A message arrives on `crypto.price.raw` that cannot be deserialised (e.g. wrong schema, null fields).
**Handling:** Spring Kafka `DefaultErrorHandler` with a `DeadLetterPublishingRecoverer` – after N retries, the message is forwarded to `crypto.price.raw.DLT` (dead letter topic) along with the original exception header.
**What to demonstrate:** Publish a malformed JSON string directly via Kafka UI and observe the DLT receiving it after retries are exhausted.

### 8.5 Consumer Lag (Slow Consumer)
**Scenario:** The portfolio service is slower than the market data producer (e.g. due to database write latency), causing consumer lag to grow.
**Handling:** Tune `max.poll.records` and `fetch.min.bytes`. For extreme lag, scale out consumer instances within the same consumer group (each partition is assigned to one instance).
**What to demonstrate:** Add an artificial `Thread.sleep` in the consumer and observe growing lag in Kafka UI, then remove the delay and show the consumer catching up.

---

## 9. Future Work – Camunda / BPM (Later Exercises)

Once the event-driven backbone is stable, Camunda 8 (or Camunda 7 embedded) will be introduced for the following process-oriented use cases:

| BPMN Process | Description |
|---|---|
| **Automated Trading Workflow** | A user-defined rule ("if BTC drops 5% in 1 h, sell 20%") is modelled as a BPMN process. Camunda orchestrates the steps: evaluate condition → validate portfolio balance → call `trading-service` → await `OrderExecutedEvent` → notify user. |
| **Portfolio Rebalancing Process** | Periodic BPMN process that checks if portfolio allocation has drifted beyond thresholds and generates rebalancing orders. |
| **User Onboarding Process** | BPMN process for new user registration: create account → send welcome email → create default portfolio → trigger initial portfolio snapshot. |

The key architectural distinction this introduces is **orchestration** (Camunda tells services what to do) versus **choreography** (services react to events independently), allowing a direct comparison of both coordination styles in the same codebase.

---

## 10. Technology Decisions

| Decision | Choice | Rationale |
|---|---|---|
| JVM | Java 21 | LTS release, virtual threads (Project Loom) beneficial for I/O-heavy consumers |
| Framework | Spring Boot 3.x | Native Spring Kafka integration, mature ecosystem, auto-configuration |
| Messaging | Apache Kafka | Durable, partitioned log; fits all four EDA patterns; required by exercise |
| Containerisation | Docker + Compose | Reproducible local dev, simple CI |
| Database | PostgreSQL | Portfolio state persistence; well-supported via Spring Data JPA |
| Binance Integration | Public WebSocket API (no key needed) | `wss://stream.binance.com:9443/ws/<symbol>@ticker` stream, real-time push delivery |
| Build | Maven (multi-module) | Allows shared `shared-events` module depended on by both services |
| Kafka Serialisation | JSON (Jackson) | Simpler setup for MVP; can migrate to Avro + Schema Registry later |

---

*Document version: 1.0 – March 2026*
