# 6. Subscribe to Binance WebSocket streams for market data

Date: 2026-03-01

## Status

Accepted

## Context

The market-data-service needs a source of live cryptocurrency prices. We evaluated three options:

- **Binance WebSocket stream:** Sub-second push delivery via `wss://stream.binance.com:9443/ws/<symbol>@ticker`. Requires persistent connection management (reconnection logic, heartbeats, ping/pong handling). Delivers a truly event-driven pipeline end-to-end.
- **Paid market data provider (e.g. CoinGecko Pro, CryptoCompare):** Richer data and SLAs. Requires API keys, billing, and vendor lock-in — unnecessary for a university project.
- **Binance public REST API (polling):** Simple HTTP GET on a fixed schedule. No credentials, no persistent connections, no cost. However, introduces a pull-based step in an otherwise event-driven architecture and adds up to 10 seconds of artificial latency.

## Decision

We subscribe to Binance WebSocket streams (`wss://stream.binance.com:9443/ws/<symbol>@ticker`) using a Spring WebSocket client. Each configured symbol gets a stream subscription, and price updates are pushed to us in real time. No API key is required.

## Consequences

- **Zero cost and no credentials:** The Binance WebSocket API is public — any team member can run the service immediately without registration.
- **Event-driven end-to-end:** The market-data-service receives push updates from Binance and forwards them to Kafka. There is no polling step, making the entire pipeline reactive.
- **Sub-second latency:** Prices arrive as soon as Binance publishes them, rather than being up to 10 seconds stale.
- **Connection lifecycle management:** The service must handle WebSocket connection drops, reconnections with exponential backoff, and Binance ping/pong heartbeats. This is more complex than a simple `@Scheduled` HTTP call but is well-supported by Spring's WebSocket client.
- **Variable event rate:** The event rate is dictated by Binance (market activity), not by a fixed schedule. During high volatility more events arrive; during quiet periods fewer. This is natural for an event-driven system.
- **Graceful degradation:** If the WebSocket connection drops, the service reconnects automatically. During the disconnection window, no events are published — consumers continue serving queries from their cached state (ECST).
