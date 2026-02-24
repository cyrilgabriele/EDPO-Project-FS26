# Producer Experiments
> [!NOTE]
>
> In this experiment, we will demonstrate real message loss.

## Overview

We will use the setup of the [lab02Part3-ManyBrokers](https://github.com/scs-edpo/lab02Part3-ManyBrokers) for this.
Only the differences will be pointed out here to the original version of the infrastructure and components.
You can find the full description of the setup in the original repository.

## Infrastructure

The infrastructure consists of three Docker services defined in [docker-compose.yml](docker-compose.yml):

1. **controller**: A dedicated node responsible for cluster metadata and leadership election.
1. **kafka1**: Broker node.
1. **kafka2**: Another broker node.

The configurations of the **Controller** and **Brokers** are the same as in the original lab.

## Components

1. **ClickStream-Producer**
   - The producer generates a random click event every `150ms`.
   - `retries=0`: If the leader is not available, the producer won't resend the message.
   - `acks=0`: The leader won't wait for the broker's acknowledgement.

1. **ClickStream-Consumer**
   - The consumer consumes the messages from the topic.

## Tutorial: Message Loss

Follow these steps to simulate message loss:

1. Navigate to the docker directory:
    ```bash
    cd assignments/ex-1/producer-experiments
    ```
1. Start the cluster:
    ```bash
    docker compose up -d
    ```
   _Wait until all applications are healthy._
1. Start `ClickStream-Producer` by running the corresponding run configuration in IntelliJ.
1. Start `ClickStream-Consumer` by running the corresponding run configuration in IntelliJ.
1. Kill the leader broker:
    - Identify which broker is the leader (e.g., if leader is 2, it corresponds to `kafka1`).
    - Stop that container:
        ```bash
        docker stop producer-experiments-kafka1-1
        ```
1. Observe the producer's and consumer's logs:
   - The last message sent by the producer before the new leader was elected should be lost.
   - See if you can identify the missing eventID.

## Observations

1. The producer's logs show the following:
    ```txt
    ...
    clickEvent sent: eventID: 75, timestamp: 42282243148875, xPosition: 201, yPosition: 592, clickedElement: EL6,
    clickEvent sent: eventID: 76, timestamp: 42282399315208, xPosition: 412, yPosition: 795, clickedElement: EL9,
    Current Leader: 2 host: localhost port: 9092
    In Sync Replicates: [2]
    clickEvent sent: eventID: 77, timestamp: 42282556626000, xPosition: 606, yPosition: 1025, clickedElement: EL9,
    clickEvent sent: eventID: 78, timestamp: 42282713050041, xPosition: 813, yPosition: 201, clickedElement: EL17,
    ...
    ```
1. The consumer's logs show the following:
    ```txt
    ...
    Received click-events - value: {eventID=75, timestamp=42282243148875, xPosition=201, yPosition=592, clickedElement=EL6}- partition: 0
    Received click-events - value: {eventID=77, timestamp=42282556626000, xPosition=606, yPosition=1025, clickedElement=EL9}- partition: 0
    Received click-events - value: {eventID=78, timestamp=42282713050041, xPosition=813, yPosition=201, clickedElement=EL17}- partition: 0
    ...
    ```
   
### What happend?

- The producer's message with the `eventID=76` was lost.
- The misconfigured producer caused this message loss.
  - `acks=0` means that the producer won't wait for the broker's acknowledgement. 
  - `retries=0` means that the producer won't resend the message when the leader is not available.
- This completely disables the fault tolerance of Kafka. The producer will always report success, 
but the message will never appear in the topic.
- The broker logs might show nothing, because the producer's message never reached the broker.
- **The message is lost forever**.

### How to fix this?

- In this setup we have to use `acks=all` and `retries > 0`.
  - `acks=1` in a 2-broker cluster means the producer waits for the leader's acknowledgement.
    - This does not guarantee the replication to the follower (second broker).
    - There still might be **message loss**.
    - But this **reduces latency** and **improves availability**.
  - If `acks=all`, then the producer waits for the acknowledgement from all brokers.
    - This guarantees the message is replicated to all brokers, **strong durability**.
    - But this causes **higher latency**, must wait for replication.
  - `retries > 0` means the producer will resend the message when the leader is not available.
    - With `retries=5` the producer will resend the message up to five times.
      - This **might cause duplicate messages** in the topic, 
      - but **improves fault tolerance** if the leader is not available and has not acknowledged the message yet.
    - Additionally set `enable.idempotence=true` to **avoid duplicate messages**.

## Cleanup

1. Stop the `ClickStream-Consumer`.
1. Stop the `ClickStream-Producer`.
1. Stop the cluster:
    ```bash
    docker compose down -v
    ```
