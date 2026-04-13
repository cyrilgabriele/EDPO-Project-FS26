= Live System Demonstration <demonstration>

CryptoFlow ships a purpose-built dashboard for each service. Every page polls its own backend on a one- to five-second interval and renders the current system state without any manual refresh. The screenshots below were taken during a live run with all five services and the Camunda 8 SaaS cluster active.

== market-data-service — Event Notification

#figure(
  image("figures/market-data-demo.png", width: 100%),
  caption: [market-data-service dashboard showing the live Kafka event stream],
) <fig:demo-market-data>

The market-data-service dashboard (@fig:demo-market-data) shows the raw events arriving from the Binance WebSocket feed and being published to the `crypto.price.raw` Kafka topic. Each row corresponds to one Kafka record and exposes the symbol, USDT price, partition, offset, the original exchange timestamp, the time the event was published by the producer, and the full event UUID. The offset column increases monotonically per partition, making it straightforward to confirm that no events are dropped. The producer is unaware of the downstream consumers, embodying the 'fire and forget' principle of the Event Notification pattern.

== portfolio-service — Event-Carried State Transfer

#figure(
  image("figures/portfolio-demo.png", width: 100%),
  caption: [portfolio-service dashboard showing the local price cache and all portfolio holdings],
) <fig:demo-portfolio>

The portfolio-service dashboard (@fig:demo-portfolio) has two sections. The upper section renders the service's in-memory `LocalPriceCache`, which is implemented as a `ConcurrentHashMap` that is updated by a dedicated Kafka consumer listening on the same `crypto.price.raw` topic. Because the cache is populated by consuming events rather than by querying the market-data-service at request time, no HTTP call to port 8081 is ever made when the dashboard loads. This is the defining property of Event-Carried State Transfer: the consumer owns a local, always-fresh replica of the data it needs.

The lower section shows each portfolio with the user's name, their UUID, and a holdings table listing every cryptocurrency position, its current quantity, the live price served from the local cache, the resulting portfolio value, and the timestamp at which the holding was first created. The small propagation delay visible between the order approval time in the transaction-service and the `Added At` timestamp in the portfolio card illustrates the end-to-end latency introduced by the asynchronous event flow.

== transaction-service — Transactional Outbox and Replicated Read-Model

#figure(
  image("figures/transaction-demo.png", width: 100%),
  caption: [transaction-service dashboard showing orders, outbox events, and the local confirmed-user projection],
) <fig:demo-transaction>

The transaction-service dashboard (@fig:demo-transaction) is divided into three sections. The Orders table lists all placed orders with their status (`PENDING`, `APPROVED`, or `REJECTED`), the target price specified by the user, the matched market price that triggered the transition, and the timestamps for placement and resolution. Orders remain `PENDING` until the Zeebe price-check job worker finds a live Binance price at or below the target. Only then does the Zeebe workflow advance and the `approveOrderWorker` write the `APPROVED` status.

The Outbox Events table confirms the Transactional Outbox pattern: each approved order has a corresponding row in the `outbox_event` table that was written atomically in the same database transaction as the status update. A scheduler running every 500 ms reads unpublished rows, publishes them to Kafka, and marks them as published. The `Published At` timestamp and the checkmark in the State column prove that the event has left the service's local store. So long as the database transaction commits, the event will eventually be published. This eliminates the the dual-write problem.

The Confirmed Users section shows the service's local `confirmed_user` projection, which is populated by consuming `UserConfirmedEvent` messages from Kafka. Order validation reads this table to check whether a requesting user has completed onboarding, without making a synchronous call to the onboarding-service. This is the Replicated Read-Model pattern: each service keeps a local, eventually-consistent copy of the data it depends on, trading some storage for autonomy and resilience.

== onboarding-service — Parallel Saga via Camunda

#figure(
  image("figures/onboarding-demo.png", width: 100%),
  caption: [onboarding-service dashboard showing live Camunda process instances enriched with user variables],
) <fig:demo-onboarding>

The onboarding-service dashboard (@fig:demo-onboarding) queries the Camunda Operate REST API and displays the twenty most recent instances of the `UserOnboarding` BPMN process. Each row shows the instance state, the user name, email address, and generated user UUID resolved from Zeebe process variables, the full instance key, and the start and end timestamps. Active instances have a pulsing green state badge, while completed instances are rendered in a muted style.

The dashboard is filtered to the latest deployed version of the process definition, so re-deployments during development do not mix old and new instances in the same view. Enriching the instance list with user-level variables requires one Operate variable query per instance per variable name; the results are joined client-side before the response is sent to the browser. An error banner appears if the Operate API is unreachable, making connectivity issues immediately visible without breaking the rest of the page.
