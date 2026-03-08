## Consumer Experiments (`./consumer-experiments`)
### Shared Preparation
- Topic `click-events` with a single partition is created by the provided producer (`ClickStream-Producer/src/main/java/...`).
- Producer emits ordered `eventID` values `1..20` (and beyond) before each test.
- Consumers log every `eventID`. When expecting `auto.offset.reset` to apply, a fresh `group.id` is configured (`consumer.properties`).

### Experiment A — Safe Replay with `auto.offset.reset=earliest`
**Goal:** Confirm that when no committed offsets exist, `earliest` forces a full rewind.

**Procedure:**
1. Produce the first batch of events before starting the consumer.
2. Start the consumer with the defaults (`group.id=grp1`, `auto.offset.reset=earliest`).
3. Kill the consumer before it auto-commits (Ctrl+C within five seconds), then restart it unchanged.

**Observed behavior:**

![Experiment A shutdown](./screenshots/experimentA_img1.png)

- Shutdown while printing events `45–48` proves offsets were never committed.

![Experiment A replay](./screenshots/experimentA_img2.png)

- Restart log shows “Resetting offset … offset=0” and the consumer replays from `eventID=0` in order.

**Insights:**
- Within the retention window, missing commits + `earliest` guarantee deterministic replay, which is ideal for at-least-once processing and disaster recovery.
- Operationally, you must budget for the fact that a restart can take as long as processing the full backlog again.

### Experiment B — History Skipped with `auto.offset.reset=latest`
**Goal:** Show that switching to `latest` causes brand-new consumer groups to miss retained data if they have no offsets.

**Procedure:**
1. Keep producing to `click-events` and edit `consumer.properties` to use `group.id=grp2` and `auto.offset.reset=latest`.
2. Start the consumer, observe no records being printed initially, then produce more events.

**Observed behavior:**

![Experiment B reset to tail](./screenshots/experimentB_img1.png)

- Client joins `grp2` with no offsets and immediately resets to offset 90.

![Experiment B skipped history](./screenshots/experimentB_img2.png)

- Producer emits IDs `0..6` before the consumer prints anything; those remain unread by `grp2`.

**Insights:**
- `latest` is unsafe for analytics-style workloads that expect replay of retained data; you must explicitly use `earliest`, manual `seek`, or pre-seed offsets to prevent silent data gaps.
- Even though Kafka retained the skipped records, from the application’s perspective the data is “lost,” illustrating the misconfiguration risk discussed in the README.
