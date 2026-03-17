# 4. Use trading symbol as Kafka partition key

Date: 2026-03-01

## Status

Accepted

## Context

Kafka topics are divided into partitions. The message key determines which partition a message
lands in. We need a partitioning strategy for the `crypto.price.raw` topic (3 partitions) that
preserves ordering where it matters.

Alternatives considered:

- **Running number / UUID (unique per message):** Distributes messages evenly via hashing, but
  events for the same symbol can land in different partitions, destroying per-symbol ordering.
  A consumer reading partition 1 might see a newer BTCUSDT price before an older one still
  sitting in partition 2.
- **No key (null):** Kafka uses sticky partitioning (batch to one partition, then rotate).
  Same problem: no per-symbol ordering.
- **Symbol as key:** All events for BTCUSDT always route to the same partition. Within that
  partition, Kafka preserves insertion order. This guarantees chronological processing per symbol.

## Decision

The Kafka message key is the trading symbol (e.g. `BTCUSDT`). Partition assignment uses a
deterministic symbol-index mapping (`symbolIndex % numPartitions`) in `CryptoPriceKafkaProducer`
rather than Kafka's default Murmur2 hash. For a small, fixed set of symbols this guarantees
even distribution across partitions while preserving per-symbol ordering. Unknown symbols
fall back to a hash-based assignment.

## Consequences

- **Per-symbol ordering:** Kafka guarantees ordering within a partition. Consumers always
  process price updates for a given symbol in chronological order, preventing stale prices
  from overwriting newer ones in the local ECST cache (ADR-0002).
- **Deterministic distribution:** The explicit index-based mapping avoids Murmur2 hash
  collisions that could concentrate multiple symbols onto the same partition for a small
  symbol set. Partition assignments are logged at startup for operational transparency.
- **Shared key by design:** Unlike database primary keys, Kafka message keys are routing
  keys, not unique identifiers. Hundreds of messages sharing the key `BTCUSDT` is intended
  behaviour. The event's `eventId` (UUID) serves as the unique identifier.
- **Parallelism:** With 3 partitions, up to 3 consumer instances in the same group can
  process events concurrently.
- **Potential skew:** If symbol count grows unevenly beyond the partition count, some
  partitions will carry more symbols than others. Not a concern at the current scale
  (6 symbols, 3 partitions).
