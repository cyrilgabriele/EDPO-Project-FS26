# CryptoFlow – Event-driven Crypto Portfolio Platform

> [!NOTE]
> Copyright 2026 - present [Cyril Gabriele](mailto:cyril.gabriele@student.unisg.ch), [Ioannis Theodosiadis](mailto:ioannis.theodosiadis@student.unisg.ch), University of St. Gallen
>
> Course: **Event-driven and Process-oriented Architectures (EDPO), FS2026** – Exercise 2

---

## What is CryptoFlow?

CryptoFlow is a crypto portfolio simulation platform built to demonstrate event-driven architecture patterns using Apache Kafka and Spring Boot. Two microservices communicate **exclusively via Kafka** – there is no REST call between them:

- **`market-data-service`** subscribes to Binance WebSocket streams and publishes real-time price events per symbol to Kafka.
- **`portfolio-service`** consumes those events and maintains a local price replica, which it uses to answer portfolio valuation queries via its own REST API.

```
  Binance WebSocket API
        │  wss://stream.binance.com:9443/ws/<symbol>@ticker
        ▼
┌──────────────────────┐         Topic: crypto.price.raw          ┌──────────────────────┐
│  market-data-service │ ────────────────────────────────────────▶│  portfolio-service   │
│  (Producer)          │   CryptoPriceUpdatedEvent per symbol     │  (Consumer + REST)   │
│  port 8081           │                                          │  port 8082           │
└──────────────────────┘                                          └──────────────────────┘
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Java | 21 (JDK) |
| Maven | 3.9+ |
| Docker + Docker Compose | any recent version |

---

## Getting Started

### Option A – Run everything in Docker (recommended)

```bash
# 1. Clone and enter the repo
git clone <repo-url>
cd EDPO-Project-HS26

# 2. Start the full stack (infrastructure + both services)
cd docker
docker compose up -d

# 3. Check that all containers are healthy
docker compose ps
```

All seven containers start in dependency order:
`zookeeper` → `kafka` → `kafka-ui` + `postgres` → `pgadmin` + `market-data-service` → `portfolio-service`

### Option B – Infrastructure in Docker, services locally

```bash
# Start only the infrastructure
cd docker
docker compose up -d zookeeper kafka kafka-ui postgres

# In one terminal – start the producer
cd ..
mvn spring-boot:run -pl market-data-service

# In another terminal – start the consumer
mvn spring-boot:run -pl portfolio-service
```

Both services connect to `localhost:9092` (Kafka) and `localhost:5432` (Postgres) by default.

---

## How the Market Data Service Works (Producer)

### Binance WebSocket stream

On startup, `BinanceWebSocketClient` opens a persistent WebSocket connection to Binance and subscribes to ticker streams for the configured symbols:

```
wss://stream.binance.com:9443/ws/btcusdt@ticker/ethusdt@ticker/solusdt@ticker/bnbusdt@ticker/xrpusdt@ticker
```

This is a **public endpoint** – no API key needed. Binance pushes ticker updates in real time:

```json
{
  "e": "24hrTicker",
  "s": "BTCUSDT",
  "c": "95241.32",
  ...
}
```

### Event production

For each incoming ticker message, `PriceEventMapper` wraps it in a `CryptoPriceUpdatedEvent` (a Java record with a fresh UUID `eventId`, symbol, price, and timestamp) and `CryptoPriceKafkaProducer` sends it to Kafka:

- **Topic:** `crypto.price.raw` (3 partitions)
- **Message key:** the symbol string (e.g. `BTCUSDT`) — this guarantees all events for one symbol always land on the **same partition**, preserving per-symbol ordering.
- **Serialisation:** JSON (Jackson)

The event rate is determined by Binance (market activity), not a fixed schedule — events arrive in real time.

### Failure handling

If the WebSocket connection drops, `BinanceWebSocketClient` automatically reconnects with exponential backoff. During the disconnection window, no events are published — consumers continue serving queries from their cached state (ECST).

---

## How the Portfolio Service Works (Consumer)

### Kafka consumption (ECST pattern)

`PriceEventConsumer` is annotated with `@KafkaListener` and belongs to consumer group `portfolio-service-group`. Every time a `CryptoPriceUpdatedEvent` arrives on `crypto.price.raw`, it updates `LocalPriceCache` — a `ConcurrentHashMap<String, BigDecimal>` in memory.

This implements **Event-carried State Transfer**: the portfolio service **never** calls market-data-service directly. It maintains its own local price replica and can answer queries even while market-data-service is offline.

### REST query API

The cached prices power three endpoints:

| Endpoint | Description |
|---|---|
| `GET /prices` | All currently cached symbol → price pairs |
| `GET /prices/{symbol}` | Latest price for one symbol (503 if not yet received) |
| `GET /portfolios/{userId}` | Portfolio holdings with current valuations |
| `GET /portfolios/{userId}/value` | Total portfolio value in USDT |

---

## Verifying the Event Flow

### 1. Kafka UI (easiest)

Open **http://localhost:8080** in your browser.

- **Topics** tab → click `crypto.price.raw` → **Messages** tab
- You will see new messages arriving in real time as Binance pushes ticker updates
- Each message shows: key = symbol (e.g. `BTCUSDT`), value = JSON event, partition, offset

### 2. market-data-service logs

```bash
# Docker
docker compose logs -f market-data-service

# Local
mvn spring-boot:run -pl market-data-service
```

Look for lines like:
```
Published price event for BTCUSDT → partition=1 offset=42
Published price event for ETHUSDT → partition=0 offset=41
```
(These are at `DEBUG` level — set `logging.level.ch.unisg.cryptoflow=DEBUG` in application.yml to see them, or they appear by default if run in dev mode.)

### 3. portfolio-service logs

```bash
docker compose logs -f portfolio-service
```

Look for:
```
Consumed price event: eventId=... symbol=BTCUSDT price=95241.32
```

### 4. portfolio-service REST API

After a few seconds of runtime, prices are cached and you can query them:

```bash
# All cached prices
curl http://localhost:8082/prices

# Single symbol
curl http://localhost:8082/prices/BTCUSDT

# Example response:
# {"symbol":"BTCUSDT","price":95241.32}
```

---

## Kafka Topics

| Topic | Partitions | Retention | Purpose |
|---|---|---|---|
| `crypto.price.raw` | 3 | 1 h (default) | Live price ticks from Binance |
| `crypto.price.raw.DLT` | 1 | 7 d | Dead letter topic for poison pills |

---

## Configuration Reference

### market-data-service (`application.yml`)

| Property | Default | Env var override |
|---|---|---|
| `binance.stream-url` | `wss://stream.binance.com:9443/ws` | `BINANCE_STREAM_URL` |
| `binance.symbols` | `BTCUSDT,ETHUSDT,SOLUSDT,BNBUSDT,XRPUSDT` | — |
| `spring.kafka.bootstrap-servers` | `localhost:9092` | `KAFKA_BOOTSTRAP_SERVERS` |

### portfolio-service (`application.yml`)

| Property | Default | Env var override |
|---|---|---|
| `spring.kafka.bootstrap-servers` | `localhost:9092` | `KAFKA_BOOTSTRAP_SERVERS` |
| `spring.datasource.url` | `jdbc:postgresql://localhost:5432/cryptoflow` | `SPRING_DATASOURCE_URL` |
| `spring.datasource.username` | `cryptoflow` | `SPRING_DATASOURCE_USERNAME` |
| `spring.datasource.password` | `cryptoflow` | `SPRING_DATASOURCE_PASSWORD` |

---

## Repository Layout

```
EDPO-Project-HS26/
├── pom.xml                          ← Maven parent POM (multi-module)
│
├── shared-events/                   ← Shared Kafka event DTOs (Java records)
│   └── .../events/CryptoPriceUpdatedEvent.java
│
├── market-data-service/             ← Producer (port 8081)
│   ├── adapter/in/binance/           ← Binance WebSocket stream client
│   ├── adapter/out/kafka/           ← KafkaTemplate producer
│   ├── application/                 ← PriceEventMapper
│   ├── domain/                      ← PriceTick domain object
│   └── Dockerfile
│
├── portfolio-service/               ← Consumer + REST API (port 8082)
│   ├── adapter/in/kafka/            ← @KafkaListener consumer
│   ├── adapter/in/web/              ← REST controllers (prices, portfolios)
│   ├── adapter/out/persistence/     ← JPA entities + Flyway migration
│   ├── application/                 ← PortfolioService (valuation logic)
│   ├── domain/                      ← LocalPriceCache (ECST)
│   └── Dockerfile
│
├── docker/
│   ├── docker-compose.yml           ← Full local stack
│   └── README.md                    ← Docker quick-start guide
│
├── docs/                            ← Architecture docs (see PROJECT_ARCHITECTURE.md)
└── assignments/                     ← Course assignment materials
```

---

## EDA Patterns Demonstrated

| Pattern | Where |
|---|---|
| **Event Notification** | `market-data-service` receives Binance stream updates and emits price events with no knowledge of who consumes them. Adding a new consumer requires zero changes to the producer. |
| **Event-carried State Transfer (ECST)** | `portfolio-service` maintains a local price replica from Kafka events. It never calls `market-data-service` directly, making it resilient to producer downtime. |

See [`PROJECT_ARCHITECTURE.md`](docs/PROJECT_ARCHITECTURE.md) for the full design document.

---

## Team

| Name | Contribution                                                          |
|---|-----------------------------------------------------------------------|
| Ioannis Theodosiadis | Architecture, project structure, portfolio-service |
| Cyril Gabriele | Architecture, market-data-service                                     |
