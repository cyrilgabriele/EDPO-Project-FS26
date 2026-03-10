# 5. Use a monorepo with a shared library for event schemas

Date: 2026-03-01

## Status

Accepted

## Context

The producer and consumer must agree on event schemas (`CryptoPriceUpdatedEvent`). Options include: a shared library module in a monorepo, duplicating DTOs in each service, or using a schema registry with code generation.

## Decision

We use a Maven multi-module monorepo. Event records live in a shared library (`shared-events` module) that both `market-data-service` and `portfolio-service` depend on as a compile-time dependency.

## Consequences

- **Single source of truth:** Event schemas are defined once. Compile-time type safety ensures producer and consumer stay in sync.
- **Atomic changes:** A schema change and its consumers can be updated in a single commit/PR.
- **Tight coupling at build time:** Both services must be built from the same repository. Independent deployment requires careful versioning of the shared library.
- **Monorepo overhead:** All services share a single CI pipeline and Git history. Acceptable for a small team and 2-3 services, but may not scale to many independent teams.
- **Alternative rejected:** Schema Registry with code generation was rejected for the MVP due to additional infrastructure overhead (see ADR-0003).
