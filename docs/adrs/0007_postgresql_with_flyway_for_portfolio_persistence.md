# 7. Use PostgreSQL with Flyway for portfolio persistence

Date: 2026-03-01

## Status

Accepted

## Context

The portfolio-service needs to persist portfolio holdings across restarts. We need to choose a database and a schema management strategy. Options include: relational DB with ORM, NoSQL document store, or purely in-memory state rebuilt from Kafka on startup.

## Decision

We use PostgreSQL 16 as the relational database, Spring Data JPA for data access, and Flyway for versioned schema migrations. Hibernate's `ddl-auto` is set to `validate` (never modifies the schema).

## Consequences

- **Reliable persistence:** Portfolio data survives service restarts without replaying Kafka history.
- **Explicit schema management:** Flyway migrations are versioned SQL files in source control, providing a clear audit trail of schema changes.
- **Safety:** `ddl-auto: validate` prevents Hibernate from silently altering the production schema. Schema changes must go through a deliberate migration.
- **Operational overhead:** Requires a running PostgreSQL instance. Adds a container and a health-check dependency to the startup sequence.
- **Alternative rejected:** Rebuilding state from Kafka on startup was rejected because Kafka topic retention (1 hour for `crypto.price.raw`) is too short, and portfolio data is not event-sourced in the MVP.
