# CryptoFlow – GitHub Issues Backlog

> Copy each issue block below into GitHub as an individual issue.
> Suggested labels are listed per issue. Create these labels in your repo first.
>
> **Labels to create:**
> `epic`, `setup`, `backend`, `kafka`, `documentation`, `error-handling`, `docker`, `testing`, `stretch`

---

## EPIC 0 – Project Setup

---

### Issue #1 – Initialise monorepo and Maven parent POM

**Labels:** `epic`, `setup`
**Assignee:** both
**Status:** ✅ Done

**Description:**
Create the top-level repository structure as defined in the architecture document. Set up a Maven multi-module parent POM so that `market-data-service`, `portfolio-service`, and `shared-events` can all be built from the root with a single `mvn install`.

**Acceptance Criteria:**
- [x] Repository contains the directory skeleton: `market-data-service/`, `portfolio-service/`, `shared-events/`, `docker/`, `docs/`
- [x] Root `pom.xml` declares the three submodules
- [x] `mvn clean install` from the root succeeds (even with empty Spring Boot starters)
- [x] Each service has a working `Spring Boot 3` + `Java 21` starter app that starts without errors
- [x] `.gitignore` excludes `target/`, `.idea/`, `*.class`

---

### Issue #2 – Set up Docker Compose for local infrastructure

**Labels:** `setup`, `docker`
**Assignee:** both
**Status:** ✅ Done

**Description:**
Create a `docker/docker-compose.yml` that starts the full local infrastructure required for development: Zookeeper, Kafka broker, Kafka UI (provectuslabs/kafka-ui), and PostgreSQL.

**Acceptance Criteria:**
- [x] `docker compose up` in `docker/` starts all infrastructure services without errors
- [x] Kafka is accessible at `localhost:9092`
- [x] Kafka UI is accessible at `http://localhost:8080`
- [x] PostgreSQL is accessible at `localhost:5432` with a `cryptoflow` database
- [x] A `README` note in `docker/` explains how to start/stop the stack
- [x] Both Spring Boot services can be started locally (outside Docker) and connect to the Dockerised infrastructure

---

### Issue #3 – Define shared Kafka event DTOs in `shared-events` module

**Labels:** `setup`, `kafka`, `backend`
**Assignee:** (assign one person)
**Status:** ✅ Done

**Description:**
Create the `shared-events` Maven module that defines all Kafka event classes as Java records. Both `market-data-service` and `portfolio-service` will depend on this module. This avoids duplicating event schema definitions.

**Acceptance Criteria:**
- [x] `shared-events` module exists and is listed in the parent POM
- [x] `CryptoPriceUpdatedEvent` record is defined with fields: `eventId` (UUID), `symbol` (String), `price` (BigDecimal), `timestamp` (Instant)
- [x] Both service POMs declare `shared-events` as a dependency
- [ ] Jackson serialisation/deserialisation of the record works in a unit test
- [x] Javadoc comment on each record and field explaining its purpose

---

### Issue #4 – Configure Kafka topics and Spring Kafka base settings

**Labels:** `setup`, `kafka`
**Assignee:** (assign one person)
**Status:** ✅ Done

**Description:**
Configure Kafka topic creation and shared Kafka producer/consumer settings in both services. Topics should be created programmatically via Spring's `NewTopic` beans so the setup is reproducible without manual Kafka CLI commands.

**Acceptance Criteria:**
- [x] Topic `crypto.price.raw` is created with 3 partitions and replication factor 1
- [x] Topic `crypto.price.raw.DLT` is created with 1 partition (dead letter topic)
- [x] Producer settings: `acks=all`, JSON serialiser with `CryptoPriceUpdatedEvent` as value type
- [x] Consumer settings: consumer group `portfolio-service-group`, `auto.offset.reset=earliest`, JSON deserialiser
- [x] Both topics are visible in Kafka UI after starting the services

---

## EPIC 1 – Market Data Service (Producer)

---

### Issue #5 – Implement Binance REST API client

**Labels:** `backend`, `kafka`
**Assignee:** (assign one person)
**Status:** ✅ Done

**Description:**
Implement a Spring `WebClient`-based HTTP client that calls the Binance public REST API to fetch the latest prices for a configurable list of trading symbols.

**Endpoint:** `GET https://api.binance.com/api/v3/ticker/price?symbols=["BTCUSDT","ETHUSDT","SOLUSDT","BNBUSDT","XRPUSDT"]`

**Acceptance Criteria:**
- [x] `BinanceApiClient` class uses Spring `WebClient` (not RestTemplate)
- [x] The list of symbols to fetch is externalised in `application.yml` (e.g. `binance.symbols`)
- [x] The client returns a list of `PriceTick` domain objects mapping symbol and price
- [x] Returns an empty list (and logs a warning) if the API call fails, rather than throwing an uncaught exception
- [ ] A unit test mocks the WebClient and verifies correct parsing of the Binance response JSON

---

### Issue #6 – Implement scheduled polling and Kafka price event producer

**Labels:** `backend`, `kafka`
**Assignee:** (assign one person)
**Status:** ✅ Done

**Description:**
Wire the Binance API client to a Spring `@Scheduled` task that runs on a configurable interval and publishes one `CryptoPriceUpdatedEvent` per symbol to the Kafka topic `crypto.price.raw`. The trading symbol is used as the Kafka message key.

**Acceptance Criteria:**
- [x] `@Scheduled(fixedRateString = "${binance.poll-interval-ms}")` drives polling (default: 10000 ms)
- [x] One Kafka message is published per symbol per poll cycle
- [x] The Kafka message key is the symbol string (e.g. `"BTCUSDT"`) to ensure partition affinity
- [x] Each `CryptoPriceUpdatedEvent` has a fresh UUID `eventId`
- [x] Producer logs the number of events published per cycle at `DEBUG` level
- [ ] Events are visible in Kafka UI with correct key/value structure (runtime verification)

---

### Issue #7 – Implement error handling for Binance API failures (DLQ & retry)

**Labels:** `backend`, `error-handling`
**Assignee:** (assign one person)
**Status:** 🔲 Not started

**Description:**
Add resilience to the Binance API polling. If the API is unavailable, the service must retry with exponential backoff and not crash. Document the failure mode clearly so it can be demonstrated.

**Acceptance Criteria:**
- [ ] `@Retryable` (Spring Retry) on the API call: max 3 attempts, initial backoff 1 s, multiplier 2
- [ ] After max retries, a `@Recover` method logs the error and the polling cycle is skipped (no event published)
- [ ] A metric counter or log message clearly marks each failed poll cycle
- [ ] A section in `docs/` describes how to reproduce the failure (e.g. change API base URL in `application.yml`) and what to observe

---

### Issue #8 – Dockerise `market-data-service`

**Labels:** `docker`
**Assignee:** (assign one person)
**Status:** ✅ Done

**Description:**
Write a `Dockerfile` for `market-data-service` and add it to the Docker Compose stack so the service can run alongside Kafka without a local JDK.

**Acceptance Criteria:**
- [x] Multi-stage `Dockerfile`: build stage (Maven + JDK 21), runtime stage (JRE 21 slim)
- [x] Service starts correctly via `docker compose up` alongside Kafka and Postgres
- [x] `KAFKA_BOOTSTRAP_SERVERS` and `BINANCE_POLL_INTERVAL_MS` are injectable via environment variables
- [x] Container health check is defined in `Dockerfile`

---

## EPIC 2 – Portfolio Service (Consumer + State)

---

### Issue #9 – Implement Kafka consumer for price events (ECST pattern)

**Labels:** `backend`, `kafka`
**Assignee:** (assign one person)
**Status:** ✅ Done

**Description:**
Implement a `@KafkaListener` in the portfolio service that consumes `CryptoPriceUpdatedEvent` messages from `crypto.price.raw` and updates a local in-memory price cache. This implements the **Event-carried State Transfer** pattern: the portfolio service never calls `market-data-service` directly.

**Acceptance Criteria:**
- [x] `@KafkaListener(topics = "crypto.price.raw", groupId = "portfolio-service-group")` consumes events
- [x] `LocalPriceCache` (a `ConcurrentHashMap<String, BigDecimal>`) is updated on each event
- [x] Consumer logs received events at `DEBUG` level, including symbol and price
- [x] Consumer handles `null` or malformed events gracefully (does not crash)
- [ ] A unit test verifies that the cache is correctly updated after a consumed event

---

### Issue #10 – Implement idempotent consumer logic

**Labels:** `backend`, `kafka`, `error-handling`
**Assignee:** (assign one person)
**Status:** 🔲 Not started

**Description:**
The Kafka producer uses at-least-once delivery semantics, meaning the portfolio service may receive the same event twice (same `eventId`). Add idempotency logic so that duplicate events are silently ignored.

**Acceptance Criteria:**
- [ ] A Caffeine in-memory cache stores recently processed `eventId` values with a 60-second TTL
- [ ] Before processing, the consumer checks if `eventId` has been seen; if yes, it skips and logs at `DEBUG`
- [ ] A unit test publishes the same event twice and verifies the price cache is updated only once
- [ ] Document this scenario in `docs/` as an error scenario demonstration

---

### Issue #11 – Implement Dead Letter Topic handling (poison pill scenario)

**Labels:** `backend`, `kafka`, `error-handling`
**Assignee:** (assign one person)
**Status:** 🔲 Not started

**Description:**
Configure Spring Kafka error handling so that messages which cannot be deserialised or processed after retries are forwarded to the dead letter topic `crypto.price.raw.DLT` instead of blocking the consumer.

**Acceptance Criteria:**
- [ ] `DefaultErrorHandler` configured with `DeadLetterPublishingRecoverer` pointing to `crypto.price.raw.DLT`
- [ ] Retry policy: 3 attempts with 500 ms backoff before sending to DLT
- [ ] DLT messages include the original exception in a Kafka header
- [ ] A manual test procedure is documented: publish a malformed string via Kafka UI, observe DLT in Kafka UI
- [ ] The consumer continues processing subsequent valid messages after a poison pill is moved to DLT

---

### Issue #12 – Implement portfolio domain model and persistence

**Labels:** `backend`
**Assignee:** (assign one person)
**Status:** ✅ Done

**Description:**
Define the core portfolio domain: a `Portfolio` entity belonging to a user, containing a list of `Holding` entries (symbol + quantity + average purchase price). Persist this to PostgreSQL using Spring Data JPA.

**Acceptance Criteria:**
- [x] `Portfolio` JPA entity with `id`, `userId`, and a `@OneToMany` collection of `Holding`
- [x] `Holding` JPA entity with `symbol`, `quantity` (BigDecimal), `averagePurchasePrice` (BigDecimal)
- [x] `PortfolioRepository` and `HoldingRepository` Spring Data interfaces
- [x] A database schema migration (Flyway or Liquibase) creates the required tables on startup
- [ ] A unit test verifies save and retrieval of a portfolio via the repository

---

### Issue #13 – Implement portfolio valuation REST API (CQRS read model)

**Labels:** `backend`
**Assignee:** (assign one person)
**Status:** ✅ Done

**Description:**
Expose REST endpoints that allow a client to query the current portfolio value and individual holdings. The portfolio service calculates the current value using its local price cache (from ECST), not by calling any external service.

**Endpoints to implement:**
- `GET /portfolios/{userId}` – returns portfolio with current valuation per holding
- `GET /portfolios/{userId}/value` – returns total portfolio value in USDT
- `GET /prices/{symbol}` – returns the latest known price for a symbol from the local cache

**Acceptance Criteria:**
- [x] All three endpoints return correct JSON responses
- [x] Portfolio value is calculated as `sum(holding.quantity * localPriceCache.get(symbol))`
- [x] Returns `404` if user portfolio does not exist
- [x] Returns `503` with a meaningful message if a symbol price is not yet in the local cache
- [ ] Integration test using `@SpringBootTest` with a mocked Kafka consumer verifies endpoint responses

---

### Issue #14 – Dockerise `portfolio-service`

**Labels:** `docker`
**Assignee:** (assign one person)
**Status:** ✅ Done

**Description:**
Write a `Dockerfile` for `portfolio-service` and integrate it into the Docker Compose stack.

**Acceptance Criteria:**
- [x] Multi-stage `Dockerfile` (build + runtime), mirroring the market-data-service approach
- [x] Service connects to Postgres and Kafka from Docker Compose
- [x] `KAFKA_BOOTSTRAP_SERVERS`, `SPRING_DATASOURCE_URL`, and other config are injectable via env vars
- [x] Service is reachable at `http://localhost:8082` after `docker compose up`

---

## EPIC 3 – Documentation

---

### Issue #15 – Write root `README.md`

**Labels:** `documentation`
**Assignee:** both
**Status:** 🔲 Not started

**Description:**
Write the project-level README that serves as the entry point for anyone (including course assessors) looking at the repository. It should explain the project's purpose, architecture at a high level, and give complete instructions to run the full stack locally.

**Acceptance Criteria:**
- [ ] Project description (2–3 sentences)
- [ ] Architecture diagram (ASCII or linked image) showing the two services and Kafka
- [ ] Prerequisites section (Docker, Java 21, Maven)
- [ ] "Getting Started" section: clone → `docker compose up` → `mvn spring-boot:run` for each service
- [ ] Section listing Kafka topics and their purpose
- [ ] Section listing REST endpoints exposed by `portfolio-service`
- [ ] Team member contributions section (required by exercise hand-in instructions)
- [ ] Link to `docs/architecture/PROJECT_ARCHITECTURE.md`

---

### Issue #16 – Write EDA patterns documentation

**Labels:** `documentation`
**Assignee:** (assign one person)
**Status:** 🔲 Not started

**Description:**
Write a dedicated documentation file `docs/architecture/eda-patterns.md` that explains exactly which EDA patterns from Lecture 2 are used in the project, where they are implemented, and why they were chosen. This document will be a key part of the graded report.

**Acceptance Criteria:**
- [ ] Covers **Event Notification** with a concrete example from the codebase (class names, topic names)
- [ ] Covers **Event-carried State Transfer** with explanation of why synchronous coupling is avoided
- [ ] Explains the trade-off: staleness of local cache vs. resilience to downstream failures
- [ ] Each pattern section references the relevant lecture definition
- [ ] Includes a sequence diagram (Mermaid or PlantUML) for each pattern showing the message flow

---

### Issue #17 – Write error scenario demonstration guide

**Labels:** `documentation`, `error-handling`
**Assignee:** (assign one person)
**Status:** 🔲 Not started

**Description:**
Document each error scenario from the architecture document as a step-by-step demonstration guide. This will be used both for the report and for any live demo during the course.

**Acceptance Criteria:**
- [ ] Scenario 1: Binance API unavailability – steps to reproduce, what to observe in logs
- [ ] Scenario 2: Consumer restart and at-least-once redelivery – how to kill/restart container
- [ ] Scenario 3: Duplicate event / idempotent consumer – how to publish duplicate via Kafka UI
- [ ] Scenario 4: Poison pill / DLT – how to publish malformed message, where DLT message appears
- [ ] Each scenario includes: preconditions, steps, expected outcome, actual log/output snippets

---

### Issue #18 – Write Architecture Decision Records (ADRs)

**Labels:** `documentation`
**Assignee:** (assign one person)
**Status:** 🔲 Not started

**Description:**
Create lightweight Architecture Decision Records for the key technical decisions made in the project. This demonstrates design thinking for the academic report.

**ADRs to write (in `docs/architecture/adr/`):**

- `ADR-001-kafka-over-rest.md` – Why Kafka instead of synchronous REST between services
- `ADR-002-ecst-pattern.md` – Why ECST instead of request/response for price data in portfolio service
- `ADR-003-json-serialisation.md` – Why JSON instead of Avro for event serialisation (with acknowledged trade-offs)
- `ADR-004-monorepo.md` – Why monorepo instead of separate repositories

**Each ADR must follow the format:** Title · Status · Context · Decision · Consequences

---

## EPIC 4 – CI & Quality

---

### Issue #19 – Set up GitHub Actions CI pipeline

**Labels:** `setup`, `testing`
**Assignee:** (assign one person)
**Status:** 🔲 Not started

**Description:**
Create a GitHub Actions workflow that builds and tests the entire project on every push and pull request to `main`.

**Acceptance Criteria:**
- [ ] `.github/workflows/build.yml` triggers on `push` and `pull_request` to `main`
- [ ] Pipeline runs `mvn clean verify` from the root (builds all modules)
- [ ] Pipeline uses Java 21 (Temurin or Corretto)
- [ ] Build passes on the default branch after setup issues are resolved
- [ ] Badge is added to `README.md` showing build status

---

### Issue #20 – Write integration test: end-to-end event flow

**Labels:** `testing`, `kafka`
**Assignee:** (assign one person)
**Status:** 🔲 Not started

**Description:**
Write a Spring Boot integration test that verifies the full end-to-end event flow: publish a `CryptoPriceUpdatedEvent` to the test Kafka topic and assert that the portfolio service's local price cache is updated.

**Acceptance Criteria:**
- [ ] Uses `@EmbeddedKafka` (Spring Kafka test support) – no external broker needed for the test
- [ ] Test publishes a `CryptoPriceUpdatedEvent` for `BTCUSDT` with price `50000`
- [ ] Test asserts that the `LocalPriceCache` contains `BTCUSDT → 50000` within 5 seconds
- [ ] Test verifies that a duplicate event (same `eventId`) does not trigger a second cache update

---

## EPIC 5 – Stretch Goals (Post-MVP)

---

### Issue #21 – Add `notification-service` (Event Notification pattern demo)

**Labels:** `backend`, `kafka`, `stretch`
**Status:** 🔲 Not started

**Description:**
Add a third microservice `notification-service` that subscribes to `crypto.price.raw` independently and logs (or sends a simulated email) whenever a tracked price crosses a user-configured threshold. This serves as the purest demonstration of the **Event Notification** pattern: the producer is completely unaware of this new consumer.

**Acceptance Criteria:**
- [ ] `notification-service` starts independently and joins the `notification-service-group` consumer group
- [ ] Alert thresholds are configurable in `application.yml`
- [ ] Console log clearly shows a "PRICE ALERT" when threshold is crossed
- [ ] Adding this service requires zero changes to `market-data-service`

---

### Issue #22 – Implement portfolio transaction history (Event Sourcing sketch)

**Labels:** `backend`, `stretch`
**Status:** 🔲 Not started

**Description:**
Store each simulated buy/sell action as an immutable `PortfolioTransactionEvent` in the database instead of (or in addition to) updating a mutable portfolio row. Allow querying the portfolio state at a past point in time by replaying events up to a timestamp.

**Acceptance Criteria:**
- [ ] `PortfolioTransactionEvent` entity with `eventId`, `userId`, `symbol`, `type` (BUY/SELL), `quantity`, `price`, `timestamp`
- [ ] `GET /portfolios/{userId}/history` endpoint returns the full event log
- [ ] `GET /portfolios/{userId}/value?at=<ISO timestamp>` returns the portfolio value at a past point in time

---

---

## EPIC 6 – Implementation Sprint 1 (Review)

> These three issues document the work completed in the initial implementation sprint.
> They are intended to be opened as pull-request-linked issues and reviewed by the other team member.

---

### Issue #23 – Refactor `market-data-service`: hexagonal structure + REST-based Binance polling

**Labels:** `backend`, `kafka`, `setup`
**Assignee:** Ioannis Theodosiadis
**Status:** ✅ Done – ready for review

**Description:**
The initial prototype used a flat single-module Maven project (`ch.unisg.kafka.spring`) with a Binance **WebSocket** stream. This issue covers the full refactor into a properly structured `market-data-service` submodule aligned with the architecture document.

**Changes made:**
- Converted root `pom.xml` to a multi-module parent POM (Spring Boot 3.5.11, spring-kafka 3.3.13, Java 21)
- Created `shared-events` submodule with `CryptoPriceUpdatedEvent` (Java record, Javadoc)
- Renamed all packages from `ch.unisg.kafka.spring` → `ch.unisg.cryptoflow.marketdata`
- Replaced WebSocket ingest with REST polling via `WebClient` (`GET /api/v3/ticker/price`)
- Applied hexagonal (ports & adapters) directory layout

**Key classes:**

| Class | Layer | Responsibility |
|---|---|---|
| `PricePollingScheduler` | `adapter/in/scheduling` | `@Scheduled` trigger every `binance.poll-interval-ms` ms |
| `BinanceApiClient` | `adapter/out/binance` | `WebClient` REST call to Binance, returns `List<PriceTick>` |
| `CryptoPriceKafkaProducer` | `adapter/out/kafka` | Publishes `CryptoPriceUpdatedEvent` keyed by symbol |
| `PriceEventMapper` | `application` | Maps `PriceTick` → `CryptoPriceUpdatedEvent` with UUID `eventId` |
| `PriceTick` | `domain` | Immutable domain record (symbol + price) |
| `KafkaTopicConfig` | `config` | Creates `crypto.price.raw` (3 partitions) and `crypto.price.raw.DLT` (1 partition) via `NewTopic` beans |

**Acceptance Criteria:**
- [x] Package structure matches `ch.unisg.cryptoflow.marketdata.adapter/application/domain/config`
- [x] `BinanceApiClient` uses `WebClient`, not `RestTemplate` or WebSocket
- [x] Configured symbols (`BTCUSDT`, `ETHUSDT`, `SOLUSDT`, `BNBUSDT`, `XRPUSDT`) are externalised in `application.yml`
- [x] Polling interval is configurable via `binance.poll-interval-ms` (default: 10 000 ms)
- [x] Each published event carries a fresh UUID `eventId` and the symbol as the Kafka key
- [x] Kafka topics `crypto.price.raw` and `crypto.price.raw.DLT` are created programmatically on startup
- [x] Binance API failures are caught and logged; the polling cycle is skipped gracefully (no exception propagates)
- [x] `mvn clean package -pl market-data-service -am` builds without errors
- [ ] Reviewer: start the service locally, open Kafka UI at http://localhost:8080, and confirm 5 messages arrive on `crypto.price.raw` every ~10 s with the symbol as the key

---

### Issue #24 – Implement `portfolio-service`: Kafka consumer, JPA persistence, REST query API

**Labels:** `backend`, `kafka`
**Assignee:** Ioannis Theodosiadis
**Status:** ✅ Done – ready for review

**Description:**
Implements the full MVP scope of `portfolio-service`: consuming price events from Kafka (ECST pattern), maintaining a local in-memory price cache, persisting the portfolio domain to PostgreSQL via JPA/Flyway, and exposing a REST query API.

**Key classes:**

| Class | Layer | Responsibility |
|---|---|---|
| `PriceEventConsumer` | `adapter/in/kafka` | `@KafkaListener` on `crypto.price.raw`; updates `LocalPriceCache` |
| `LocalPriceCache` | `domain` | `ConcurrentHashMap<String, BigDecimal>` – ECST price replica |
| `PortfolioEntity` / `HoldingEntity` | `adapter/out/persistence` | JPA entities (`portfolio` + `holding` tables) |
| `PortfolioRepository` | `adapter/out/persistence` | Spring Data `JpaRepository` |
| `PortfolioService` | `application` | Fetches portfolio; calculates `sum(qty × cachedPrice)` |
| `PortfolioController` | `adapter/in/web` | `GET /portfolios/{userId}` and `GET /portfolios/{userId}/value` |
| `PriceController` | `adapter/in/web` | `GET /prices` and `GET /prices/{symbol}` |
| `KafkaConsumerConfig` | `config` | Typed `ConsumerFactory` + `kafkaListenerContainerFactory` bean |

**Database schema** (created by Flyway `V1__create_portfolio_tables.sql`):
- `portfolio(id, user_id)` – one row per user
- `holding(id, portfolio_id, symbol, quantity, average_purchase_price)` – one row per position

**EDA patterns demonstrated:**
- **Event-carried State Transfer**: `LocalPriceCache` is populated from Kafka events; no REST call is ever made back to `market-data-service`
- **CQRS read model**: REST endpoints answer queries from the local cache + JPA, independently of the write path

**Acceptance Criteria:**
- [x] `@KafkaListener` on `crypto.price.raw` with consumer group `portfolio-service-group`
- [x] `LocalPriceCache` is updated for each valid received event; null/malformed events are skipped safely
- [x] `Portfolio` and `Holding` JPA entities with correct column types (`NUMERIC(30,18)` for quantity)
- [x] Flyway migration runs on startup and creates the required tables
- [x] `GET /prices/{symbol}` returns `200` with price, or `503` if not yet cached
- [x] `GET /portfolios/{userId}` returns `404` if the portfolio does not exist
- [x] `GET /portfolios/{userId}/value` returns `503` if any holding's symbol price is missing from cache
- [x] Total value is calculated as `sum(holding.quantity × localCache.price(symbol))` without any call to `market-data-service`
- [x] `mvn clean package -pl portfolio-service -am` builds without errors
- [ ] Reviewer: with both services running, call `curl http://localhost:8082/prices` after ~15 s and confirm all 5 symbols are cached with live prices

---

### Issue #25 – Containerise both services and complete the Docker Compose stack

**Labels:** `docker`, `setup`
**Assignee:** Ioannis Theodosiadis
**Status:** ✅ Done – ready for review

**Description:**
Adds production-grade multi-stage Dockerfiles for both services and extends the Docker Compose stack to include all infrastructure and application services. Also adds pgAdmin for direct database inspection.

**Files added / changed:**

| File | Change |
|---|---|
| `market-data-service/Dockerfile` | New – two-stage build (Maven+JDK21 → JRE21-alpine) |
| `portfolio-service/Dockerfile` | New – two-stage build (Maven+JDK21 → JRE21-alpine) |
| `docker/docker-compose.yml` | New – full local stack (see below) |
| `docker/README.md` | New – quick-start guide |

**Docker Compose services:**

| Service | Image | Port | Notes |
|---|---|---|---|
| `kafka` | `confluentinc/cp-kafka:7.6.0` | `9092` | KRaft mode |
| `kafka-ui` | `provectuslabs/kafka-ui:latest` | `8080` | Monitors topics and messages |
| `postgres` | `postgres:16-alpine` | `5432` | DB: `cryptoflow`, persistent volume |
| `pgadmin` | `dpage/pgadmin4:latest` | `5050` | Persistent volume for saved connections |
| `market-data-service` | built from source | `8081` | Depends on healthy kafka |
| `portfolio-service` | built from source | `8082` | Depends on healthy kafka + postgres |

**Dockerfile design:**
- Stage 1 copies POMs first and runs `mvn dependency:go-offline` — dependencies are cached as a separate layer so rebuilds after code-only changes are fast
- Stage 2 uses `eclipse-temurin:21-jre-alpine` (minimal runtime, ~60 MB smaller than JDK image)
- `HEALTHCHECK` polls `/actuator/health` so Docker knows when the app is ready
- All secrets/URLs are injectable via environment variables (no hardcoded values in images)

**Acceptance Criteria:**
- [x] `docker compose up -d` (from `docker/`) starts all seven services without errors
- [x] Kafka UI is accessible at http://localhost:8080
- [x] pgAdmin is accessible at http://localhost:5050 (login: `admin@cryptoflow.local` / `admin`)
- [x] `market-data-service` health endpoint responds at http://localhost:8081/actuator/health
- [x] `portfolio-service` health endpoint responds at http://localhost:8082/actuator/health
- [x] Both Dockerfiles use multi-stage builds; final image is based on JRE (not JDK)
- [x] `KAFKA_BOOTSTRAP_SERVERS`, `SPRING_DATASOURCE_URL`, and other runtime config are injectable via env vars
- [ ] Reviewer: run `docker compose up -d`, wait ~60 s for all health checks to pass, then confirm `docker compose ps` shows all containers as `healthy`
- [ ] Reviewer: connect pgAdmin to host `postgres`, port `5432`, db `cryptoflow` and inspect the `portfolio` and `holding` tables created by Flyway

---

*Backlog version: 1.1 – March 2026 (updated after initial restructuring)*
