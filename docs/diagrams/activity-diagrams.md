# Activity Diagrams

These diagrams show the current high-level business workflows in this branch. They intentionally avoid low-level transport, retry, and broker details.

## 1. User Onboarding

```mermaid
flowchart TD
    A([User starts onboarding]) --> B[Camunda starts the userOnboarding flow]
    B --> C[Collect username, email, and password]
    C --> D[user-service prepares the confirmation link]
    D --> E[Send confirmation email]
    E --> F{User confirms before the link expires?}

    F -->|No| G[user-service invalidates the confirmation link]
    G --> H([Onboarding ends without an account])

    F -->|Yes| I[user-service confirms the user and correlates Camunda]
    I --> J[Run user creation and portfolio creation in parallel]

    J --> K[user-service creates the user]
    J --> L[portfolio-service creates the portfolio]

    K --> M{Both creation steps succeeded?}
    L --> M

    M -->|Yes| N([Onboarding completed])
    M -->|No| O[Trigger compensation through Kafka]
    O --> P([Onboarding ends with rollback])
```

## 2. Order Placement

```mermaid
flowchart TD
    A([User submits an order]) --> B[Camunda starts the placeOrder flow]
    B --> C[transaction-service validates the order]
    C --> D[Store the order as pending]
    D --> E[Wait for a matching market price event]
    E --> F{Price matched before timeout?}

    F -->|No| G[Reject the order]
    G --> H[Send rejection email]
    H --> I([Order ends as not executed])

    F -->|Yes| J[Approve the order and persist the outbox entry]
    J --> K[Publish `transaction.order.approved`]
    K --> L[portfolio-service updates holdings]
    L --> M[Send execution email]
    M --> N([Order completed])
```

## 3. Portfolio Read and Valuation

```mermaid
flowchart TD
    A([Client requests portfolio data]) --> B[portfolio-service loads the portfolio]
    B --> C{Portfolio exists?}

    C -->|No| D([Return not found])
    C -->|Yes| E[Read current prices from the local cache]
    E --> F{All required prices available?}
    F -->|No| G([Return 503 while the cache is warming up])
    F -->|Yes| H[Build the response and calculate valuations]
    H --> I([Return the portfolio or valuation response])
```
