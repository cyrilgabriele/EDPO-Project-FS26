# Deployment Diagram – Docker Compose Stack

## Container Topology

```mermaid
graph TB
    subgraph host["Host Machine (localhost)"]

        subgraph docker["Docker Compose Network"]

            subgraph infra["Infrastructure Layer"]
                kafka["Kafka Broker<br/>──────────────<br/>confluentinc/cp-kafka:7.6.0<br/>──────────────<br/>Internal: kafka:29092<br/>Host: localhost:9092<br/>Controller: kafka:9093"]
                postgres["PostgreSQL<br/>──────────────<br/>postgres:16-alpine<br/>──────────────<br/>Host: localhost:5432<br/>DB: cryptoflow"]
            end

            subgraph monitoring["Monitoring & Admin"]
                kafkaui["Kafka UI<br/>──────────────<br/>provectuslabs/kafka-ui<br/>──────────────<br/>Host: localhost:8080"]
                pgadmin["pgAdmin<br/>──────────────<br/>dpage/pgadmin4<br/>──────────────<br/>Host: localhost:5050"]
            end

            subgraph services["Application Services"]
                mds["market-data-service<br/>──────────────<br/>Java 21 / Spring Boot<br/>──────────────<br/>Host: localhost:8081"]
                ps["portfolio-service<br/>──────────────<br/>Java 21 / Spring Boot<br/>──────────────<br/>Host: localhost:8082"]
            end

        end

        subgraph external["External"]
            binance["Binance WebSocket API<br/>stream.binance.com"]
        end

        subgraph volumes["Docker Volumes"]
            pgdata[("postgres-data")]
            pgadmindata[("pgadmin-data")]
        end

    end

    %% Dependencies (startup order)
    kafka -.->|healthy| kafkaui
    kafka -.->|healthy| mds
    kafka -.->|healthy| ps
    postgres -.->|healthy| pgadmin
    postgres -.->|healthy| ps

    %% Data flows
    mds -->|"produce events<br/>kafka:29092"| kafka
    kafka -->|"consume events<br/>kafka:29092"| ps
    ps -->|"JDBC<br/>postgres:5432"| postgres
    binance -->|"WSS push<br/>ticker stream"| mds
    kafkaui -->|"monitor<br/>kafka:29092"| kafka
    pgadmin -->|"admin<br/>postgres:5432"| postgres

    %% Volumes
    postgres --- pgdata
    pgadmin --- pgadmindata

    style infra fill:#e3f2fd,stroke:#1565c0
    style monitoring fill:#f3e5f5,stroke:#7b1fa2
    style services fill:#e8f5e9,stroke:#2e7d32
    style external fill:#fff8e1,stroke:#f9a825
```

## Startup Order

```mermaid
graph LR
    A["kafka<br/>"] -->|healthy| B["kafka-ui"]
    A -->|healthy| E["market-data-service"]
    A -->|healthy| F["portfolio-service"]
    C["postgres"] -->|healthy| D["pgadmin"]
    C -->|healthy| F

    style A fill:#e3f2fd,stroke:#1565c0
    style C fill:#e3f2fd,stroke:#1565c0
    style B fill:#f3e5f5,stroke:#7b1fa2
    style D fill:#f3e5f5,stroke:#7b1fa2
    style E fill:#e8f5e9,stroke:#2e7d32
    style F fill:#e8f5e9,stroke:#2e7d32
```

## Port Map

| Service | Internal Port | Host Port | URL |
|---------|--------------|-----------|-----|
| Kafka (client) | 29092 | 9092 | `localhost:9092` |
| Kafka (controller) | 9093 | — | internal only |
| Kafka UI | 8080 | 8080 | http://localhost:8080 |
| PostgreSQL | 5432 | 5432 | `localhost:5432` |
| pgAdmin | 80 | 5050 | http://localhost:5050 |
| market-data-service | 8081 | 8081 | http://localhost:8081 |
| portfolio-service | 8082 | 8082 | http://localhost:8082 |
