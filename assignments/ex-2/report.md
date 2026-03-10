# Exercise 2 – Kafka with Spring: Implementation Report

> **Course:** Event-driven and Process-oriented Architectures (EDPO), FS2026
> **Project:** CryptoFlow – crypto portfolio simulation platform
> **Stack:** Java 21 · Spring Boot 3.5 · Spring Kafka · PostgreSQL · Docker

Project Link: [https://github.com/cyrilgabriele/EDPO-Project-FS26](https://github.com/cyrilgabriele/EDPO-Project-FS26)


---

## Issue #6 – Implement `market-data-service`

### What was implemented

A Kafka producer service that subscribes to Binance WebSocket streams and publishes real-time price events per symbol to Kafka. The service is structured as a Maven multi-module project alongside `portfolio-service`, with a shared `shared-events` module containing the event record used by both services.

**Module layout:**

- **`shared-events`** – `CryptoPriceUpdatedEvent` record, declared as a compile-time dependency by both services
- **`market-data-service`** – the producer service itself (port 8081)

The service follows hexagonal (ports & adapters) architecture:

| Layer | Package | Component |
| --- | --- | --- |
| Inbound adapter | `adapter/in/binance` | `BinanceWebSocketClient` – subscribes to Binance ticker streams, receives push updates |
| Outbound adapter | `adapter/out/kafka` | `CryptoPriceKafkaProducer` – publishes events via `KafkaTemplate` |
| Application | `application` | `PriceEventMapper` – maps `PriceTick` → `CryptoPriceUpdatedEvent` |
| Domain | `domain` | `PriceTick` record – pure domain object, no framework dependencies |

**Kafka configuration:**

- Topic `crypto.price.raw` with 3 partitions; topic `crypto.price.raw.DLT` with 1 partition, both declared as `@Bean NewTopic`
- Producer uses `acks=all` and the trading symbol (e.g. `BTCUSDT`) as the message key, guaranteeing per-symbol partition affinity and ordering
- Symbols subscribed: `BTCUSDT`, `ETHUSDT`, `SOLUSDT`, `BNBUSDT`, `XRPUSDT` (configurable); price updates arrive in real time via Binance WebSocket streams

**EDA pattern demonstrated – Event Notification:**
The producer emits a `CryptoPriceUpdatedEvent` per symbol on every cycle with no knowledge of, or dependency on, any consumer. New consumers can subscribe to `crypto.price.raw` without any change to this service.

---

## Issue #7 – Implement `portfolio-service`

### What was implemented

A Kafka consumer service that maintains a local price replica and exposes REST endpoints for portfolio and price queries. Also follows hexagonal architecture:

| Layer | Package | Component |
| --- | --- | --- |
| Inbound adapter | `adapter/in/kafka` | `PriceEventConsumer` – `@KafkaListener` on `crypto.price.raw` |
| Inbound adapter | `adapter/in/web` | `PortfolioController`, `PriceController` – REST read endpoints |
| Outbound adapter | `adapter/out/persistence` | `PortfolioEntity`, `HoldingEntity`, `PortfolioRepository` (Spring Data JPA) |
| Application | `application` | `PortfolioService` – `calculateTotalValue()` via local cache |
| Domain | `domain` | `LocalPriceCache` – `ConcurrentHashMap<String, BigDecimal>` |

**Persistence:**
Flyway manages the schema with `V1__create_portfolio_tables.sql`. Two tables:

- `portfolio` – one row per user (`id`, `user_id UNIQUE`)
- `holding` – one row per `(portfolio, symbol)` pair (`quantity NUMERIC(30,18)`, `average_purchase_price NUMERIC(30,8)`, foreign key to `portfolio` with `ON DELETE CASCADE`)

**REST endpoints:**

| Method | Path | Behaviour |
| --- | --- | --- |
| `GET` | `/portfolios/{userId}` | Returns portfolio with all holdings; 404 if user has no portfolio |
| `GET` | `/prices/{symbol}` | Returns cached price from `LocalPriceCache`; 503 if not yet received |
| `GET` | `/prices` | Returns full local price cache as `Map<String, BigDecimal>` |

**EDA pattern demonstrated – Event-Carried State Transfer (ECST):**
`PriceEventConsumer` updates `LocalPriceCache` on every received event. `PortfolioService.calculateTotalValue()` multiplies each holding's quantity by the cached price — no synchronous call to `market-data-service` is made at query time. The service continues to answer REST requests even when the producer is offline, at the cost of eventual consistency (prices lag until the stream reconnects).

---

## Issue #8 – Containerise Both Services and Complete Docker Compose Stack

### What was implemented

**Multi-stage Dockerfiles:**

1. **Build stage** (`maven:3.9-eclipse-temurin-21-alpine`): POMs are copied and `mvn dependency:go-offline` is run first, so the dependency layer is cached independently of source changes. Source is then copied and the fat JAR is built with `-DskipTests`.
2. **Runtime stage** (`eclipse-temurin:21-jre-alpine`): Only the JAR is copied into the slim JRE image. A `HEALTHCHECK` polls `/actuator/health` via `wget`.

**Docker Compose stack (`docker/docker-compose.yml`):**

| Service | Image | Port | Notes |
| --- | --- | --- | --- |
| `kafka` | `confluentinc/cp-kafka:7.6.0` | 9092 | KRaft mode; `AUTO_CREATE_TOPICS_ENABLE=false` |
| `kafka-ui` | `provectuslabs/kafka-ui:latest` | 8080 | Monitoring dashboard |
| `postgres` | `postgres:16-alpine` | 5432 | Persistent volume `postgres-data` |
| `pgadmin` | `dpage/pgadmin4:latest` | 5050 | PostgreSQL GUI |
| `market-data-service` | local build | 8081 | `depends_on kafka: service_healthy` |
| `portfolio-service` | local build | 8082 | `depends_on kafka + postgres: service_healthy` |

Kafka runs in **KRaft mode**, using two listeners: `PLAINTEXT` on `kafka:29092` for inter-service communication within the Docker network, and `PLAINTEXT_HOST` on `0.0.0.0:9092` exposed to the host. Startup ordering is enforced via `condition: service_healthy` on health-checked services.
