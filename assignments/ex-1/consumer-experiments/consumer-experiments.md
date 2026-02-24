# Consumer Experiments

## Common Preparation
- Create a topic with a single partition (deterministic offset ordering)
  - see below: already hard-coded i.e. done by default
- Produce ordered messages with sequence numbers 1..20
- Log every consumed sequence number
- When you expect `auto.offset.reset` to apply, reuse a fresh consumer group ID

## Experiment A — `auto.offset.reset=earliest`
**Goal:** Prove that consumers with `auto.offset.reset=earliest` safely replay historical data when no committed offsets exist.

1. Create topic `click-events` (already hard-coded in @assignments/ex-1/consumer-experiments/ClickStream-Producer/src/main/java/com/examples/ClicksProducer.java)
2. Produce messages `1..20` before starting the consumer.
3. Start the consumer with the defaults from @assignments/ex-1/consumer-experiments/ClickStream-Consumer/src/main/resources/consumer.properties: `group.id=grp1` and `auto.offset.reset=earliest`.
4. Observe `1,2,3,...,20` being logged in order.

### Observations (img1/img2)
![ExperimentA_img1](./screenshots/experimentA_img1.png)
Right after startup we killed the consumer with `Ctrl+C` while it was printing events `45-48` (`screenshots/experimentA_img1.png`). 
Because the shutdown happened before Kafka’s default `auto.commit.interval.ms=5000` fired, no offsets were committed.

![ExperimentA_img1](./screenshots/experimentA_img2.png)
When restarting the same binary without changing anything (`screenshots/experimentA_img2.png`), 
the client reported `Resetting offset for partition click-events-0 position FetchPosition{offset=0…}` and replayed the stream starting at `eventID=0`. 

This shows how `auto.offset.reset=earliest` plus missing commits leads to a full rewind—exactly the behaviour we want to highlight in Experiment A.

## Experiment B — `auto.offset.reset=latest`
**Goal:** Show that switching to `auto.offset.reset=latest` skips history if no offsets exist.

1. Keep producing messages `1..20` to `click-events`.
2. Update @assignments/ex-1/consumer-experiments/ClickStream-Consumer/src/main/resources/consumer.properties with: 
   - a fresh i.e. `group.id=grp2` and 
   - set `auto.offset.reset=latest`.
3. Start the consumer and notice it does **not** read the historical messages.
4. Produce new events `21..25`.
5. Only the new events appear in the consumer log; the earlier ones stay unread even though they remain in Kafka.

**What it demonstrates:** `latest` instructs Kafka to start at the end when no offsets exist. Unless you explicitly configure `earliest`, a brand-new consumer group can silently skip large amounts of available data. This is the “data loss from the client’s perspective” scenario we contrast with Experiment A.

### Observations (img1/img2)
![ExperimentB_img1](./screenshots/experimentB_img1.png) `screenshots/experimentB_img1.png` shows the consumer joining the fresh group (`grp2`) with no committed offsets and immediately resetting to `offset=90`. Because `auto.offset.reset=latest` forces Kafka to jump to the tail, the client waits for new records beyond offset 90, which explains the apparent "idle" period after startup.

![ExperimentB_img2](./screenshots/experimentB_img2.png) `screenshots/experimentB_img2.png` captures the producer already emitting canonical IDs `0..6` before the consumer prints anything. Those records remain in Kafka, but `latest` made the consumer skip them permanently; only once events >=90 were produced did the terminal start logging, illustrating the user-visible "message loss" while the data still exists on the broker.
