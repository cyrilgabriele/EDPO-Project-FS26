# Fault Tolerance and Reliability Experiments

> [!NOTE]
>
> In this experiment, we assess how Kafka behaves during broker and controller failures.
> The setup in this folder is intentionally kept partly unsafe so anti-patterns are reproducible and observable.

## Overview

This experiment builds on the same setup style as the producer experiments, but focuses on cluster fault tolerance and durability behavior under failures.

The main question is: when failures happen, do we get:

- temporary unavailability only,
- duplicates,
- or true data loss (records that were acknowledged by the producer but never consumed)?

## Infrastructure

The infrastructure in [docker-compose.yml](docker-compose.yml) contains:

1. **controller**: Single KRaft controller for cluster metadata.
1. **kafka1**: Broker node.
1. **kafka2**: Broker node.
1. **kafka3**: Broker node.

Important characteristics of this infrastructure:

- There is only one controller.
- Brokers use replication defaults suited for 3 brokers.
- `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=3` means consumer group internals are sensitive to broker outages.

## Components

1. **ClickStream-Producer**
   - Produces click events with monotonic `eventID` values (`0,1,2,...`).
   - Monitors and logs leader/ISR changes (`LEADER_ISR ...`) so message behavior can be correlated with leadership changes and ISR shrink.
   - Logs send outcome explicitly:
     - `ACKED id=<n> ...` means the record was acknowledged.
     - `SEND FAILED id=<n> ...` means the send did not complete successfully.

1. **ClickStream-Consumer**
   - Consumes `click-events`.
   - Uses `enable.auto.commit=false` and commits after processing.
   - Detects monotonic-ID gaps and logs `GAP DETECTED from=<a> to=<b> ...`.

## Common Commands

### Show leader and ISR

```bash
docker compose exec kafka1 bash -lc \
'kafka-topics --bootstrap-server kafka1:29092 --describe --topic click-events'
```

### Change topic durability controls

```bash
# min ISR = 1 (unsafe)
docker compose exec kafka1 bash -lc \
'kafka-configs --bootstrap-server kafka1:29092 --entity-type topics --entity-name click-events --alter --add-config min.insync.replicas=1'

# min ISR = 2 (safer)
docker compose exec kafka1 bash -lc \
'kafka-configs --bootstrap-server kafka1:29092 --entity-type topics --entity-name click-events --alter --add-config min.insync.replicas=2'

# keep unclean election disabled
docker compose exec kafka1 bash -lc \
'kafka-configs --bootstrap-server kafka1:29092 --entity-type topics --entity-name click-events --alter --add-config unclean.leader.election.enable=false'
```

### Failure injection helpers

```bash
docker compose stop kafka2
docker compose kill -s KILL kafka2
docker compose start kafka2
```

## 1. Tutorial: Leader Failure and Election Time

Goal: measure failover pause and behavior during a leader crash.

1. Navigate to the docker directory:
    ```bash
    cd assignments/ex-1/producer-experiments
    ```
1. Start the cluster:
    ```bash
    docker compose up -d
    ```
   _Wait until all applications are healthy._
1. Start producer and consumer (IntelliJ run configs).
1. Hard-kill current leader:
   - Identify current leader:
     ```bash
     docker compose exec kafka1 bash -lc \
     'kafka-topics --bootstrap-server kafka1:29092 --describe --topic click-events'
     ```
     Output:
     ```
     Topic: click-events     TopicId: lsO9YiIYRuCEAmV66fitfg PartitionCount: 1       ReplicationFactor: 3    Configs: min.insync.replicas=1
     Topic: click-events     Partition: 0    Leader: 4       Replicas: 4,2,3 Isr: 4,2,3      Elr:    LastKnownElr:
     ```
   - Kill the container (in this case kafka3 because the index is one lower than the ID shown in the output):
     ```bash
     docker compose kill -s KILL kafka3
     ```
1. Observe logs until stable production/consumption resumes.

### Observations

Observed in this run:

1. The last ACK before failover was `id=212` at `18:12:51.570`.
1. Leader changed from `2` to `3` and was detected at `18:13:00.375`.
1. Measured timings from producer logs:
   - `lastAckToLeaderElectedMs=8805`
   - `lastAckToFirstRecoveredAckMs=8890`
   - `firstAckAfterRecoveryMs=85` (from failover detection to first recovered ACK)
1. First recovered ACK was `id=213`, and then ACKs continued in order.
1. Consumer received a continuous sequence (`211..271`) with no gap and no duplicate in the shown window.

### What happened?

- This run shows a **temporary availability pause**, not durability loss.
- The producer kept queueing events during the pause; once the new leader was active, ACKs resumed and drained in order.
- The difference between `lastAckToFirstRecoveredAckMs` and `firstAckAfterRecoveryMs` indicates the main pause happened **before** the failover detector logged `FAILOVER_STARTED`.
- Consumer continuity (`211..271`) confirms no lost ACKed records for this run.

### Takeaways

- For this setup/run, practical producer-visible outage was about **8.9s** (`lastAck -> first recovered ACK`).
- Election-related downtime should be measured from **last successful ACK**, not only from detection of leader change.
- A temporary consumer pause during leader failover is expected and does not imply data loss by itself.
- Keep correlating `LEADER_ISR`, `FAILOVER_*`, producer ACK lines, and consumer monotonic IDs before concluding loss.

## 2. Tutorial: True Loss with `acks=1`

Goal: demonstrate that leader-only ACK can lose records on crash.

1. In producer config, set:
   - `acks=1`
   - `retries=0`
1. Restart producer.
1. Keep consumer running.
1. Kill the current leader while load is running:
   - `docker compose kill -s KILL kafkaX`
1. Let cluster recover and continue consuming.

### Observations

Expected to observe:

1. Some IDs near failure are producer-`ACKED`.
1. Consumer shows ID gaps for part of that range.

### What happened?

- With `acks=1`, ACK means "leader appended" only.
- If the leader crashes before replication to followers, records can be lost.

### How to fix this?

- Use `acks=all`.
- Use retries (`retries > 0`) to improve resilience during transient failures.
- Prefer `enable.idempotence=true` to avoid duplicates when retries happen.

## 3. Tutorial: Anti-Pattern (`acks=all` + `min.insync.replicas=1`)

Goal: show that `acks=all` alone is not enough if ISR shrinks to 1.

1. Producer config:
   - `acks=all`
   - `retries=5`
1. Topic config:
   - `docker compose exec kafka1 bash -lc 'kafka-configs --bootstrap-server kafka1:29092 --entity-type topics --entity-name click-events --alter --add-config min.insync.replicas=1'`
1. Stop two brokers:
   - `docker compose stop kafka2 kafka3`
1. Keep producing for 10-30 seconds (observe continuing `ACKED` lines).
1. Hard-kill remaining broker:
   - `docker compose kill -s KILL kafka1`
1. Start all brokers again:
   - `docker compose start kafka1 kafka2 kafka3`

### Observations

Expected to observe:

1. Records continue to be ACKed while only one ISR remains.
1. After killing the last broker, some of those ACKed records can disappear.

### What happened?

- `acks=all` means "all current ISR", not "all replicas in RF".
- If ISR has shrunk to 1, `acks=all` degenerates to single-node durability.

### How to fix this ?

- Enforce `min.insync.replicas=2` (or higher as needed).
- Keep `unclean.leader.election.enable=false` for durability-focused setups.

## Cleanup

1. Stop the consumer.
1. Stop the producer.
1. Stop the cluster:
   - `docker compose down -v`
