# 2. Use Event-Carried State Transfer for price data replication

Date: 2026-03-01

## Status

Accepted

## Context

The portfolio-service needs current cryptocurrency prices to calculate portfolio valuations. It could either query the market-data-service synchronously on each request, or maintain a local replica of prices derived from Kafka events.

## Decision

We use Event-Carried State Transfer (ECST). The portfolio-service consumes `CryptoPriceUpdatedEvent` messages and maintains a local in-memory price cache (`ConcurrentHashMap`). Portfolio valuations are computed against this cache without any call to market-data-service.

## Consequences

- **Resilience:** The portfolio-service continues to serve valuations even when market-data-service is down, using the last known prices.
- **Low latency:** No network round-trip for price lookups; valuations are computed from local memory.
- **Staleness:** Cached prices may be slightly behind real-time. With WebSocket streams the delay is sub-second under normal conditions, but during reconnection windows the cache serves the last known price.
- **Warm-up period:** After a cold start, the cache is empty until the first events arrive. The service returns HTTP 503 during this phase.
- **Memory footprint:** Negligible for the current 5 symbols, but would need review if scaled to hundreds of symbols.
