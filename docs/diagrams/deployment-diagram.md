# Deployment Diagram

```mermaid
graph LR
    subgraph compose["Docker Compose stack"]
        subgraph services["Application services"]
            mds["market-data-service"]
            us["user-service"]
            ts["transaction-service"]
            ps["portfolio-service"]
        end

        subgraph infra["Shared infrastructure"]
            kafka["Kafka"]
            postgres["PostgreSQL"]
            kafkaui["Kafka UI"]
            pgadmin["pgAdmin"]
        end
    end

    binance["Binance WebSocket API"]
    camunda["Camunda SaaS"]
    onboarding["onboarding-service module<br/>(not deployed by Compose)"]

    binance --> mds
    mds --> kafka
    us --> kafka
    ts --> kafka
    ps --> kafka

    us --> postgres
    ts --> postgres
    ps --> postgres

    kafkaui --> kafka
    pgadmin --> postgres

    onboarding -.->|"deploys userOnboarding"| camunda
    ts -.->|"deploys placeOrder"| camunda
    us -.->|"messages and jobs"| camunda
    ps -.->|"workers"| camunda

    style infra fill:#e3f2fd,stroke:#1565c0
    style services fill:#e8f5e9,stroke:#2e7d32
    style binance fill:#fff8e1,stroke:#f9a825
    style camunda fill:#fff8e1,stroke:#f9a825
    style onboarding fill:#f5f5f5,stroke:#9e9e9e,stroke-dasharray: 5 5
```

Notes:

- `docker/docker-compose.yml` runs four application services: `market-data-service`, `portfolio-service`, `transaction-service`, and `user-service`.
- `onboarding-service` exists as a module, but it is not deployed by `docker/docker-compose.yml`.
- The diagram intentionally omits port numbers, container images, and other low-value deployment detail.
