= Live System Demonstration <demonstration>

CryptoFlow ships purpose-built dashboards for the user-facing and process-facing services. Every page polls its own backend on a one- to five-second interval and renders the current system state without any manual refresh. The sections below document each demo surface, the patterns it illustrates, and the architectural decisions made visible through the live state.

== market-data-service — Event Notification, Stateful OHLC Aggregation, and Reference Data Enrichment

#figure(
  image("figures/market-data-demo.png", width: 100%),
  caption: [market-data-service dashboard showing the live Kafka event stream],
) <fig:demo-market-data>

The market-data-service dashboard (@fig:demo-market-data) makes all three ingest pipelines of the Market Data bounded context visible in a single view.

The upper panel shows a live OHLC candlestick chart. Closed bars are produced by the co-located Kafka Streams stateful topology, which aggregates raw tick events from `crypto.price.raw` into one-minute, five-minute, and one-hour windows written to `crypto.ohlc.1m`, `crypto.ohlc.5m`, and `crypto.ohlc.1h`. The interval selector switches between the three resolutions without a page reload. The summary statistics below the chart, including bar count, last close price, and percentage change over the visible window, are read directly from the local OHLC state store through an interactive query. No synchronous call to any external service is required.

When the metadata join has completed, a coin information panel appears alongside the chart. The panel shows the asset name, base/quote pair, logo, and market-cap rank sourced from `reference.crypto.metadata`. These fields are added through a `GlobalKTable` join inside the OHLC topology. Each closed bar is enriched with the latest metadata record for the same symbol before being emitted downstream. This is a concrete instance of a stateful stream join that combines a high-frequency event stream with a slow-changing reference table.

The lower panel exposes the raw `crypto.price.raw` event stream in real time. Each row corresponds to one Kafka record and shows the symbol, USDT price, partition, offset, original Binance exchange timestamp, producer publication time, and event UUID. This section illustrates the Event Notification pattern. The same source stream that drives the OHLC aggregation topology is simultaneously consumable as a continuous event feed, with no modification to the producer and no coupling between the two consumers.

== portfolio-service — Event-Carried State Transfer and Continuous Portfolio Valuation

#figure(
  image("figures/portfolio-demo.png", width: 100%),
  caption: [portfolio-service dashboard showing the local price cache, FX cache, and portfolio holdings with converted totals],
) <fig:demo-portfolio>

The portfolio-service dashboard (@fig:demo-portfolio) demonstrates Event-Carried State Transfer across three independent event streams. The USDT price cache is populated from `crypto.price.raw`, the FX rate cache from `reference.fx.rate`, and the display-currency preference cache from `user.display-currency`. Because all three caches are filled by consuming events at ingest time, no dashboard request calls market-data-service, fx-rate-service, or user-service synchronously. The service therefore has full local autonomy and can compute a converted portfolio total even when every upstream service is unreachable.

Each portfolio card shows the user name, UUID, and a one-click copy button for the user ID. A display-currency selector allows switching between currencies without a page reload. The currency conversion is computed at read time using the local USDT price cache and the current FX rate, both of which are kept up to date by the running Kafka consumers. The converted total, USDT subtotal, and active FX rate are shown alongside the holdings table, which lists per-symbol quantity, display-currency price, converted value, and creation timestamp.

The small propagation delay visible between an approved order appearing in transaction-service and the corresponding holding appearing in the portfolio illustrates the inherent latency of an asynchronous event-driven flow. This latency is the direct trade-off the architecture accepts in exchange for service autonomy and fault tolerance.

== transaction-service — Bid/Ask Matching, Transactional Outbox, and Replicated Read-Model

#figure(
  image("figures/transaction-demo.png", width: 100%),
  caption: [transaction-service dashboard showing the buy-time quote widget, order lifecycle, outbox events, confirmed-user projection, and matching audit],
) <fig:demo-transaction>

The transaction-service dashboard (@fig:demo-transaction) starts with a buy-time quote widget. It reads the user display currency from the local `user.display-currency` cache, the latest USDT price from the local `crypto.price.raw` cache, and the current FX rate from `reference.fx.rate`. The widget previews the display-currency price the user sees before placing an order through Camunda. It serves as a read-side helper, while actual order placement is handled by `placeOrder.bpmn`.

The Orders table lists all placed orders with their status (`PENDING`, `APPROVED`, or `REJECTED`), the target price specified by the user, the matched ask price that triggered the transition, and the timestamps for placement and resolution. Orders remain in the `PENDING` state until the transaction matching topology allocates a `MatchableAsk` to the order's `BuyBid` and emits a `transaction.order-matched` event. Only then does the Zeebe workflow advance and the `approveOrderWorker` write the `APPROVED` status.

The Outbox Events table demonstrates the Transactional Outbox pattern. Each approved order has a corresponding row in the `outbox_event` table that was written atomically within the same database transaction as the status update. A scheduler running every 500 ms reads unpublished rows, publishes them to Kafka, and marks them as published. The `Published At` timestamp and the checkmark in the State column confirm that the event has left the service's local store. As long as the database transaction commits, the event will eventually be delivered. This design eliminates the dual-write problem.

The Confirmed Users section shows the service's local `confirmed_user` projection, which is built by consuming `UserConfirmedEvent` messages from Kafka. It also displays the cached display currency so that a confirmed user can be selected directly in the quote widget. Order validation reads this projection to determine whether a requesting user has completed onboarding, without issuing a synchronous call to the onboarding-service or user-service. This is the Replicated Read-Model pattern, in which each service maintains a local eventually consistent copy of the data it depends on, accepting some additional storage in exchange for autonomy and resilience.

The Matching Audit section ties the stream-processing layer back to the workflow. It joins the recently observed `BuyBid`, `MatchableAsk`, and `transaction.order-matched` audit rows in the dashboard response so that each match can be inspected with bid price and quantity, ask quote ID, matched price and quantity, event-time timeline, source venue, and Kafka topic, partition, and offset metadata.

== market-order-scout-service — Stateful Windowed Aggregation and Ask-Price Distribution

#figure(
  image("figures/market-order-scout-demo.png", width: 100%),
  caption: [market-order-scout-service dashboard showing windowed minimum ask-price distributions],
) <fig:demo-market-order-scout>

The market-order-scout-service dashboard (@fig:demo-market-order-scout) consumes the materialized dashboard state exposed by its Kafka Streams topology. It shows one panel per symbol with a histogram of `log(minAskPrice)` across the retained window summaries, the number of retained windows, and the statistical moments mean, variance, skewness, and kurtosis. A separate topics section lists the raw input topic, derived ask-quote stream, matchable-ask stream, ask-opportunity stream, and window-summary topic used by the service.

== onboarding-service — Parallel Saga Orchestration via Camunda

#figure(
  image("figures/onboarding-demo.png", width: 100%),
  caption: [onboarding-service dashboard showing process instance statistics, the instance table, and the expandable BPMN process-flow panel],
) <fig:demo-onboarding>

The onboarding-service dashboard (@fig:demo-onboarding) queries the Camunda Operate REST API and presents the twenty most recent instances of the `UserOnboarding` BPMN process. The top of the page shows process-instance statistics including total, active, completed, and failed counts, giving an overview of saga health without opening Camunda Operate directly.

The instance table lists each run with its state, user name, email address, generated user UUID resolved from Zeebe process variables, full instance key, and start and end timestamps. Active instances carry a pulsing green state badge, while completed and failed instances are rendered in a muted style. An expandable process-flow section below the table renders the onboarding BPMN diagram and shows which path each instance took through the parallel user and portfolio creation branches.

The dashboard is filtered to the latest deployed version of the process definition, so re-deployments during development do not mix old and new instances in the same view. Enriching the instance list with user-level variables requires a separate Operate variable query for each displayed instance. The results are joined in the onboarding-service response before the browser renders them. An error banner is shown at the top of the page when the Operate API is unreachable, making connectivity issues immediately visible without disrupting the rest of the dashboard. This reflects the same fault-isolation principle applied across the platform, where a dependency failure degrades a single surface rather than causing a full failure.
