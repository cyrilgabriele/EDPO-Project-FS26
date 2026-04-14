= Team Responsibilities <team-responsibilities>

The project was developed by a two-person team over the course of the FS2026 semester. Both team members contributed to architectural design and system integration, while individual service ownership was divided by bounded context. We paid attention that the contribution was 50/50 among both members.

@tab:team-responsibilities summarizes the concrete ownership split and the major implementation responsibilities of each team member.

#figure(
  caption: "Overview of team responsibilities and contributions",
  table(
    columns: (auto, 1fr, 2fr),
    [*Team Member*], [*Area of Ownership*], [*Description*],
    "Ioannis Theodosiadis",
    [
      - Architecture design
      - Place order process
      - Portfolio Service
      - Transaction Service
      - Infrastructure
      - Kafka experiments
      - Documentation
    ],
    [Designed the overall system architecture and service structure. Owned and implemented the place order flow and the related transaction service logic (order matching and BPMN-based orchestration), and built the portfolio service (Kafka consumer, local price cache, REST API, JPA persistence with Flyway). Led infrastructure setup for local integration, contributed to Kafka reliability experiments, authored architecture decisions, and report documentation.],
    "Cyril Gabriele",
    [
      - Architecture design
      - Onboarding process
      - Market Data Service
      - User Service
      - Onboarding Service
      - Kafka experiments
      - Documentation
    ],
    [Co-designed the system architecture. Owned and implemented the onboarding process end to end across the onboarding service and user service, including the `userOnboarding.bpmn` orchestration, Camunda workers, confirmation handling, and compensation behavior. Built the market data service (Binance WebSocket integration and deterministic Kafka producer partitioning), contributed to Kafka reliability experiments, authored architecture decisions, and report documentation.],
  ),
) <tab:team-responsibilities>
