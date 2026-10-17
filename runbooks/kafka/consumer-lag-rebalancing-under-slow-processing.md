# Kafka consumer lag and repeated rebalancing under slow processing

During a Kafka consumer issue, lag grew during bursts and group members rebalanced while workers were busy with database processing. I treated the broker and consumer as separate parts of the problem: poll cadence, batch size and available partitions mattered as much as broker health.

## Symptoms

- Consumer lag grows during traffic spikes.
- Consumer-group membership changes repeatedly.
- Workers pause during rebalance cycles.
- Application processing is database-heavy or otherwise slower than the configured poll interval.

## Root cause

The consumers were doing enough work per poll that processing sometimes exceeded `max.poll.interval.ms`. Exceeding `max.poll.interval.ms` can cause the consumer to lose its assignment and trigger a rebalance even if heartbeat/session settings look healthy. Heartbeats do not override the maximum interval between polls. A low partition count also limited useful parallelism.

## Remediation used

### Increase parallelism deliberately

The affected topic was expanded from 2 partitions to 8 so additional consumers could process partitions concurrently.

Before increasing partitions, remember that partition count affects ordering guarantees: ordering is only preserved within a partition.

### Reduce work per poll

The consumer batch size was reduced, for example:

```properties
max.poll.records=100
```

This reduced the amount of synchronous work that had to finish before the next poll.

### Give legitimate processing enough time

The poll interval was increased from the default-style 300 seconds to 600 seconds for the workload:

```properties
max.poll.interval.ms=600000
```

`session.timeout.ms` and `heartbeat.interval.ms` were also reviewed so heartbeats remained healthy while the application processed records.

## Diagnostic workflow

1. Check consumer-group lag by partition.
2. Check application logs for rebalance/join/leave events.
3. Measure record-processing time, especially database calls.
4. Compare worst-case processing duration with `max.poll.interval.ms`.
5. Compare active consumer count with partition count.
6. Tune batch size and timing only after the bottleneck is understood.

## Validation

After the change, validate that:

- lag returns toward steady state after bursts;
- the group no longer enters continuous rebalance cycles;
- consumers remain assigned long enough to process useful work;
- database/downstream systems are not simply overwhelmed by the added parallelism.

## Lesson

Kafka consumer lag is not always a broker-capacity problem. Application processing time, partition-level parallelism, poll cadence, and downstream latency have to be analyzed together.