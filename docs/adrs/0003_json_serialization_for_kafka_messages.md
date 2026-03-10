# 3. Use JSON serialization for Kafka messages

Date: 2026-03-01

## Status

Accepted

## Context

Kafka messages need a serialization format. Common options are JSON (Jackson), Apache Avro with Schema Registry, or Protocol Buffers. The choice affects schema evolution, debugging, and operational overhead.

## Decision

We use JSON serialization via Jackson (`JsonSerializer` / `JsonDeserializer`) with type headers disabled. Event schemas are defined as Java records in the `shared-events` module.

## Consequences

- **Simplicity:** No additional infrastructure (Schema Registry) required. Easy to set up and debug.
- **Human-readable:** Messages are inspectable in Kafka UI without special tooling.
- **No schema enforcement:** There is no broker-side schema validation. A malformed message will only fail at deserialization time in the consumer.
- **No built-in schema evolution:** Renaming or removing fields requires coordinated deployment. Avro's compatibility modes would handle this automatically.
- **Larger message size:** JSON is more verbose than binary formats. Acceptable for the current low-throughput use case (~5 messages every 10 seconds).
- **Migration path:** Can migrate to Avro + Schema Registry later if schema evolution or throughput becomes a concern.
