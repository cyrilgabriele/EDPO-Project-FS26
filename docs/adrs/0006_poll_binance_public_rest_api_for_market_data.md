# 6. Poll the Binance public REST API for market data

Date: 2026-03-01

## Status

Accepted

## Context

The market-data-service needs a source of live cryptocurrency prices. We evaluated three options:

- **Binance WebSocket stream:** Sub-second push delivery. Requires persistent connection management (reconnection logic, heartbeats, backpressure handling) — complexity the service does not need given that a portfolio simulation tolerates 10-second staleness.
- **Paid market data provider (e.g. CoinGecko Pro, CryptoCompare):** Richer data and SLAs. Requires API keys, billing, and vendor lock-in — unnecessary for a university project.
- **Binance public REST API (polling):** Simple HTTP GET on a fixed schedule. No credentials, no persistent connections, no cost.

## Decision

We poll the Binance public REST API endpoint `GET /api/v3/ticker/price` on a fixed 10-second schedule using Spring's `@Scheduled` and `WebClient`. No API key is required.

## Consequences

- **Zero cost and no credentials:** Any team member can run the service immediately without registration or setup.
- **Simplicity:** A `@Scheduled` method with a `WebClient` call is trivial to implement, test, and debug. No connection lifecycle or reconnection logic.
- **Controllable load:** The producer dictates the event rate. Kafka throughput is predictable and the demo is easy to reason about.
- **Higher latency:** Prices are up to 10 seconds stale. Acceptable for a simulation, not for real trading.
- **Rate limit safety:** One request per 10 seconds is well within Binance's public limit (~1200 req/min).
- **Graceful degradation:** If the API is unreachable, the scheduler skips the cycle and logs a warning. No broken events enter Kafka.
