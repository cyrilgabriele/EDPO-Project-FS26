# 5. Use a shared library module for event schemas

Date: 2026-03-01

## Status

Accepted

## Context

Kafka producers and consumers must agree on event schemas (e.g. `CryptoPriceUpdatedEvent`).
Three options were considered:

1. **Shared library module** — define event records once in a dedicated Maven module
   (`shared-events`). All services declare a compile-time dependency on it.
2. **Duplicate DTOs per service** — each service maintains its own copy of each event class.
   No shared dependency, but schema changes require coordinated edits across all services.
3. **Schema Registry with code generation** — a broker-side registry (e.g. Confluent Schema
   Registry with Avro) enforces compatibility and auto-generates event classes. Adds
   infrastructure and a build-time code generation step (rejected for the MVP, see ADR-0003).

## Decision

Event records live in a `shared-events` Maven module that every producing and consuming service
depends on at compile time. The module contains only event schema definitions (Java records)
and their serialization dependencies (Jackson). It contains no business logic.

## Consequences

- **Single source of truth:** Event schemas are defined once. Compile-time type safety ensures
  producer and consumer stay in sync.
- **Atomic schema changes:** A schema change and all affected consumers can be updated in a
  single commit.
- **Build-time coupling:** All services that depend on `shared-events` must be rebuilt when
  the module changes. Independent deployment requires careful versioning if services are ever
  released on separate cadences.
- **No runtime schema enforcement:** There is no broker-side validation. A consumer running
  an older version of `shared-events` will fail at deserialization if the schema has changed
  incompatibly (see ADR-0003 for the Avro migration path).
