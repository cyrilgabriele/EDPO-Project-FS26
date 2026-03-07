# 4. Use trading symbol as Kafka partition key

Date: 2026-03-01

## Status

Accepted

## Context

Kafka topics are divided into partitions. The message key determines which partition a message lands in (via hash of the key). We need a partitioning strategy for the `crypto.price.raw` topic (3 partitions) that preserves ordering where it matters.

Alternatives considered:

- **Running number / UUID (unique per message):** Would distribute messages evenly across partitions via round-robin-like hashing. However, events for the same symbol could land in different partitions, destroying any ordering guarantee. A consumer reading partition 1 might see a newer BTCUSDT price before an older one still sitting in partition 2. This makes it impossible to reason about event ordering per symbol.
- **No key (null):** Kafka uses sticky partitioning (batch to one partition, then rotate). Same problem: no per-symbol ordering.
- **Symbol as key:** All events for BTCUSDT always hash to the same partition. Within that partition, Kafka preserves insertion order. This guarantees chronological processing per symbol.

## Decision

The Kafka message key is the trading symbol (e.g., `BTCUSDT`). All price events for a given symbol are routed to the same partition.

## Consequences

- **Per-symbol ordering:** Kafka guarantees ordering within a partition. Consumers always process price updates for a given symbol in chronological order, preventing stale prices from overwriting newer ones. This is critical: if a consumer processes events out of order, an older price could overwrite a newer one in the local cache (ECST), leading to incorrect portfolio valuations.
- **Same key is intentional, not a problem:** Unlike database primary keys, Kafka message keys are not unique identifiers — they are routing keys. Hundreds of messages sharing the key `BTCUSDT` is the desired behaviour. It means "all these messages belong together and must be processed in order." The event's `eventId` (UUID) serves as the unique identifier for deduplication, not the Kafka key.
- **Parallelism:** With 3 partitions, up to 3 consumer instances in the same group can process events concurrently.
- **Potential skew:** If one symbol generates disproportionately more traffic, its partition becomes a hot spot. Not a concern at the current scale (5 symbols, equal frequency), but relevant if symbol count grows unevenly.
- **Consumer group scaling:** Adding consumer instances beyond the partition count (3) yields no benefit; excess instances sit idle.
