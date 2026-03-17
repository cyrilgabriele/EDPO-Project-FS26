# 7. Portfolio-service as sole data owner of the portfolio bounded context

Date: 2026-03-01

## Status

Accepted

## Context

The portfolio-service manages portfolio holdings and valuations. Other services
(transaction-service, user-service) interact with portfolio data indirectly — transaction
outcomes affect holdings, and users own portfolios. Two questions must be answered:

1. **Who may write to portfolio data?** If multiple services share direct database access,
   schema changes, constraint enforcement, and transactional consistency become coordination
   problems across teams and deployment cycles.
2. **How is the schema managed?** Hibernate's `ddl-auto` can silently alter tables at startup.
   In a shared-database environment this is dangerous; even in a single-owner model, implicit
   schema changes are difficult to audit or roll back.

## Decision

Portfolio-service is the exclusive owner of the portfolio bounded context. No other service
reads from or writes to its database tables. Cross-service references use opaque identifiers
(`user_id` is a plain string, not a foreign key to a user-service table). Any service that
needs to mutate portfolio state does so by publishing a Kafka event that portfolio-service
consumes (ADR-0001).

Persistence uses PostgreSQL 16 with Spring Data JPA. Schema changes are managed exclusively
through Flyway versioned migrations. Hibernate's `ddl-auto` is set to `validate` — it verifies
the schema at startup but never modifies it.

## Consequences

- **Clear ownership boundary:** Portfolio tables are portfolio-service's private implementation
  detail. Schema changes, index tuning, and data migrations are local decisions that do not
  require coordination with other teams.
- **No cross-service joins:** Other services cannot query portfolio tables directly. They must
  either consume Kafka events carrying portfolio state or call portfolio-service's REST API
  (exposed to external clients only, per ADR-0001).
- **Explicit schema evolution:** Flyway migrations are versioned SQL files in source control.
  Every schema change is reviewable, auditable, and reproducible across environments.
- **Startup safety:** `ddl-auto: validate` prevents Hibernate from silently altering the
  production schema. A mismatch between entity definitions and the database fails fast at
  startup rather than corrupting data at runtime.
- **Operational dependency:** Portfolio-service requires a running PostgreSQL instance. The
  database container and a health check are part of the deployment sequence.
- **Alternative rejected:** Rebuilding portfolio state from Kafka on startup was rejected
  because topic retention is 1 hour (ADR-0001) and portfolio data is not event-sourced.
