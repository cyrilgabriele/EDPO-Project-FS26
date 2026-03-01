## Conversation Summary (MVP System Design Decisions)

### Goal
- Design an MVP pipeline using **Spring Boot + Docker + Kafka** to:
  1) consume real-time market data from Binance WebSockets, and  
  2) do something simple downstream (e.g., emit an event like `boughtCurrency` / `boughtSwap` based on a rule).

### Chosen Binance Data Source (stream)
- We focused on **All Market Rolling Window Statistics**:
  - Stream form: `!ticker_<window-size>@arr` (window sizes include `1h`, `4h`, `1d`).
- Key behavioral decision:
  - This stream sends **an array of tickers every ~1000ms**, but it is **delta-based**:
    - **only symbols whose stats changed appear in a given update**
    - it is **not** “every symbol every second.”
- If a “full market view” is needed, the suggested pattern is:
  - **REST snapshot at startup** + **keep updated via delta WS stream**.

### Data Contract: what each per-symbol object contains
For each symbol element within the WS array, fields include:
- Event metadata: `e`, `E`, `s`
- Rolling-window price/OHLC: `o`, `h`, `l`, `c`, `p`, `P`, `w`
- Rolling-window volume: `v`, `q`
- Window boundaries: `O`, `C`
- Trade IDs / counts: `F`, `L`, `n`

### MVP Architecture (services and flow)
- We converged on a simple 2-service setup:
  1) **Market Ingestor** (WebSocket client + Kafka producer)
     - connects to Binance WS stream
     - **splits each WS array** into **one Kafka record per symbol**
     - writes to a market topic
  2) **Signal Engine** (Kafka consumer + producer)
     - reads per-symbol updates
     - applies a simple rule (e.g., `P > X`)
     - emits a downstream event such as `boughtCurrency` / `boughtSwap` to another topic

### Kafka record keying + scaling decision
- Important design choice: Kafka message **key = `symbol`** (e.g., `BTCUSDT`)
  - preserves ordering per symbol (within a partition)
  - makes scaling consumers via consumer groups straightforward

### Diagram review outcome
- Your diagram was **conceptually correct** for the MVP.
- Suggested clarifications to make it technically precise:
  - represent the “pink events” as **Kafka topics** (records live inside topics)
  - label Signal Engine as **consumer + producer**
  - keep in mind Kafka is the broker; services run alongside it (even if all in docker-compose)

### Kafka topic structure (what we decided / recommended)
We discussed two viable structures:

#### Option A — True MVP (2 topics)
1) `market.rolling.1h`
   - per-symbol normalized records (fan-out from WS array)
   - key: `symbol`
2) `trade.events`
   - emitted signals/events such as `boughtCurrency`
   - key: `symbol` (or an event id)

#### Option B — Still small, but more “production-shaped” (3–5 topics)
1) `market.rolling.1h.raw` (optional)
   - raw WS messages for debugging/replay
2) `market.rolling.1h`
   - normalized per-symbol records (main pipeline topic)
3) `market.rolling.1h.latest` (recommended)
   - **compacted** topic to retain the latest known state per symbol
4) `trade.events`
5) `*.dlq` topics (optional but recommended)
   - for parse/validation failures

### Event format guidance
- Even if the payload is raw Binance JSON initially, we recommended wrapping it in a small envelope (source/window/eventTime/symbol + data) to keep the system evolvable (e.g., later Avro/Protobuf).

### Operational notes captured during design
- The stream is delta-based, so downstream systems must not assume “missing symbol = removed”; it usually means “no update this interval.”
- We noted practical WS realities (reconnect/backoff) and that per-symbol streams don’t scale well for “all-market” usage (vs one all-market stream + fan-out).

### Final MVP direction
- Use **`!ticker_1h@arr`** (or `4h` if you want less noise) as the source.
- Build:
  - **Market Ingestor** → Kafka topic `market.rolling.1h` (keyed by symbol, 1 msg per symbol update)
  - **Signal Engine** → Kafka topic `trade.events` (emit `boughtCurrency/boughtSwap` when rule triggers)
