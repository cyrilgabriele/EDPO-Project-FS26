# EDPO-HS26 – Kafka Experiment Harness

This repository now bundles the Kafka lab assets together with the helper tooling that we need for the Exercise 1 experiments. The goal is to spin up either a single broker (for producer/consumer tuning) or a three-broker cluster (for the fault-tolerance scenarios), run the Java sample workloads, and capture throughput/latency numbers in a reproducible way.

## Repository Layout
- `infra/docker` – docker compose files for the single broker and the three-broker (controller + 3 brokers) cluster. JMX is exposed on every broker so we can scrape metrics.
- `apps/simple-producer` & `apps/simple-consumer` – instrumented Java clients derived from Lab02 Part1. They emit per-run statistics, accept environment overrides (batch size, linger, topics, etc.), and embed a `producedAt` timestamp to let us compute end-to-end latency.
- `apps/eye-tracking` – code from Lab02 Part2 (click-stream & eye-tracker producers plus consumers). Added `DynamicEyeTrackingConsumer` so we can quickly vary consumer group sizes, partitions, and lag without editing Java every time.
- `scripts` – helper shell scripts to create topics, run the Kafka perf tools, and monitor consumer lag / container resource usage.

## Prerequisites
- Docker Desktop (or compatible) with Compose v2.
- Java 17 + Maven for the client code.
- GNU `bash`, `docker`, and `docker compose` available in `$PATH`.

## Bring Kafka Up
Single broker (used for the producer/consumer configuration experiments):
```bash
docker compose -f infra/docker/docker-compose.single-broker.yml up -d
```
Three-broker cluster (used for failover/leader-election experiments):
```bash
docker compose -f infra/docker/docker-compose.multi-broker.yml up -d
```
Tear down with `docker compose ... down -v` and clean volumes between runs if you want a fresh state.

## Helper Scripts
All scripts live under `scripts/` and accept overrides via environment variables so the same script works for both Docker environments.

| Script | Purpose | Example |
| --- | --- | --- |
| `scripts/create-topic.sh <topic> [partitions] [replication]` | Creates a topic in the running cluster. Override `COMPOSE_FILE`, `BROKER_SERVICE`, and `BOOTSTRAP` if you target the multi-broker stack. | `COMPOSE_FILE=infra/docker/docker-compose.multi-broker.yml BROKER_SERVICE=kafka1 BOOTSTRAP=localhost:9092 scripts/create-topic.sh user-events 6 3` |
| `scripts/producer-perf.sh <topic> [num-records] [record-size]` | Wraps `kafka-producer-perf-test` so you can benchmark different `acks/batch.size/linger` combinations quickly. Override props via `PRODUCER_PROPS="acks=1,batch.size=131072,linger.ms=50"`. | `PRODUCER_PROPS="acks=all,batch.size=16384,linger.ms=0" scripts/producer-perf.sh user-events 200000 512` |
| `scripts/consumer-perf.sh <topic> [messages]` | Wraps `kafka-consumer-perf-test` to stress the consumer side. | `THREADS=3 scripts/consumer-perf.sh user-events 500000` |
| `scripts/monitor.sh` | Periodically prints consumer lag (`kafka-consumer-groups --describe`), topic layout, and `docker stats`. Override `GROUP`, `TOPIC`, `INTERVAL`, and `CONTAINERS` to focus on a subset. | `GROUP=eye-tracker INTERVAL=15 scripts/monitor.sh` |

## Build the Java Workloads
Run Maven from each module to generate the runnable jars + launcher scripts:
```bash
mvn -q -f apps/simple-producer/pom.xml package
mvn -q -f apps/simple-consumer/pom.xml package
mvn -q -f apps/eye-tracking/EyeTrackers-Producer/pom.xml package
mvn -q -f apps/eye-tracking/ClickStream-Producer/pom.xml package
mvn -q -f apps/eye-tracking/consumer/pom.xml package
```
Each build drops a helper launcher (`producer`, `consumer`, etc.) inside the module’s `target/` directory so you can run them without a classpath dance.

### Instrumented Producer (apps/simple-producer)
Environment variables you can toggle per run:
- `PRODUCER_TOPIC`, `GLOBAL_TOPIC` – defaults `user-events` / `global-events`.
- `MESSAGE_COUNT`, `PAYLOAD_SIZE`, `GLOBAL_EVERY`, `FLUSH_EVERY` – shape the workload.
- `BOOTSTRAP_SERVERS`, `ACKS`, `LINGER_MS`, `BATCH_SIZE`, `COMPRESSION_TYPE`, `CLIENT_ID` – override the Kafka client properties without editing the file.
- `REPORT_INTERVAL_MS` – controls how often stats are printed.
The producer prints throughput and average request latency, so you can capture the trade-offs when you vary batch size, linger, and `acks`.

### Instrumented Consumer (apps/simple-consumer)
Environment variables:
- `CONSUMER_TOPICS` – comma-separated list to subscribe to.
- `GROUP_ID`, `AUTO_OFFSET_RESET`, `MAX_POLL_INTERVAL_MS`, `MAX_POLL_RECORDS`, `BOOTSTRAP_SERVERS` – override the usual Kafka consumer props.
- `PROCESSING_DELAY_MS` + `PROCESSING_JITTER_MS` – inject artificial delays to create lag.
- `REPORT_INTERVAL_MS` – print cadence; `PRINT_RECORDS=true` echoes each message.
The consumer computes end-to-end latency from the embedded `producedAt` field in the payload and reports per-topic averages + max latency.

### Eye-tracking Workload (apps/eye-tracking)
- `EyeTrackers-Producer` now stamps events with `System.currentTimeMillis()` so we can reason about latency.
- `consumer/src/main/java/com/examples/DynamicEyeTrackingConsumer.java` exposes environment knobs (`GROUP_ID`, `PROCESSING_DELAY_MS`, `FORCE_PARTITION`, etc.) and logs rebalances. Use this class for the multi-consumer / consumer-lag scenarios.
- Existing specialized consumers/producers from the lab are still available if you want to reproduce specific lecture demos.

## Running the Suggested Experiments
1. **Producer – Batch Size vs Latency**
   - Start the single broker compose file, create a topic with `scripts/create-topic.sh user-events 3 1`.
   - Build and run `apps/simple-producer` twice: once with `BATCH_SIZE=16384 LINGER_MS=0 REPORT_INTERVAL_MS=2000` and once with `BATCH_SIZE=131072 LINGER_MS=50`. Capture stdout plus `scripts/monitor.sh` output.
   - Optionally cross-check using `scripts/producer-perf.sh` to compare against the CLI perf tool.
2. **Consumer – Multiple Consumers & Groups**
   - Replay the eye-tracking workload (`apps/eye-tracking/EyeTrackers-Producer/target/producer`).
   - Launch 3× `DynamicEyeTrackingConsumer` instances with the same `GROUP_ID=eye-tracker` to watch partition assignment and lag, then add/remove an instance to trigger rebalances. Use `PROCESSING_DELAY_MS` to amplify lag.
   - Switch to unique `GROUP_ID`s to demonstrate broadcast semantics and note the per-consumer throughput (`scripts/monitor.sh GROUP=eye-tracker`).
3. **Fault Tolerance – Broker Failures & Leader Election**
   - Start the multi-broker compose stack and create a replicated topic (`scripts/create-topic.sh gaze-events 6 3 ...`).
   - Run the simple producer with `ACKS=all` and the instrumented consumer in parallel.
   - Kill `kafka2` (`docker compose -f infra/docker/docker-compose.multi-broker.yml stop kafka2`) and log the timestamps where `scripts/monitor.sh` shows new leaders plus producer retries. Repeat with `acks=1` and/or a replication factor of 1 to document message-loss risk.

These pieces give you a reproducible harness for every bullet point in the assignment: you can tweak configurations via env vars, collect metrics from stdout + JMX, and automate topic/broker maintenance via the helper scripts.
