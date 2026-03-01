# EDPO-FS26 – Event-driven and Process-oriented Architectures
> [!NOTE]
> Copyright 2026 - present [Cyril Gabriele](mailto:cyril.gabriele@student.unisg.ch), [Ioannis Theodosiadis](mailto:ioannis.theodosiadis@student.unisg.ch), University of St. Gallen
> 
> In this repository you can find all assignments and related exercises for the course.
> 

## Overview
- [Assignment 1](./assignments/ex-1/experiments.md)

## Running the Binance Ingest Service
1. `docker compose up` (from the repo root) only starts the Kafka broker defined in `docker-compose.yml`. Keep it running so the Spring application can publish to `localhost:9092`.
2. In a separate terminal, run the Spring Boot app with `mvn spring-boot:run`. This launches the ingest service, opens the Binance WebSocket, and logs every published delta (look for `Publishing Binance delta...`).
3. When you are done, stop the Spring app (`Ctrl+C`) and then shut down the Docker stack (`docker compose down`).
