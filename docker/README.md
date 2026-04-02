# Docker – Local Infrastructure

## Starting the full stack

From the `docker/` directory, make sure `.env` exists and contains the Camunda variables needed by
`portfolio-service`, `transaction-service`, and `user-service`. If you do not already have one,
create it from the example first:

```bash
cp .env.example .env
# then fill in the Camunda values if needed
```

Start the stack from this branch:

```bash
docker compose up -d --build
```

This compose stack currently includes Kafka in KRaft mode, Kafka UI, PostgreSQL, pgAdmin, and four
application services. `onboarding-service` exists as a Maven module but is not part of
`docker-compose.yml` in this branch.

| Service | URL / Connection |
|---|---|
| Kafka broker | `localhost:9092` |
| Kafka UI | http://localhost:8080 |
| PostgreSQL | `localhost:5432` (`cryptoflow` user, per-service DBs: `user_service_db`, `portfolio_service_db`, `transaction_service_db`) |
| pgAdmin | http://localhost:5050 |
| market-data-service | http://localhost:8081 |
| portfolio-service | http://localhost:8082 |
| transaction-service | http://localhost:8083 |
| user-service | http://localhost:8084 |

## Starting infrastructure only

For local Spring Boot runs, start only the shared infrastructure:

```bash
docker compose up -d kafka kafka-ui postgres pgadmin
```

Then run the services you want from the repo root:

```bash
# market-data-service
mvn spring-boot:run -pl market-data-service

# portfolio-service
KAFKA_BOOTSTRAP_SERVERS=localhost:9092 \
mvn spring-boot:run -pl portfolio-service

# transaction-service
mvn spring-boot:run -pl transaction-service

# user-service
KAFKA_BOOTSTRAP_SERVERS=localhost:9092 \
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/user_service_db \
mvn spring-boot:run -pl user-service
```

`portfolio-service`, `transaction-service`, and `user-service` also require their corresponding
`CAMUNDA_*` environment variables when run locally.

## Stopping

```bash
# Stop containers, keep volumes
docker compose down

# Full reset (removes all data, including PostgreSQL and pgAdmin volumes)
docker compose down -v
```
