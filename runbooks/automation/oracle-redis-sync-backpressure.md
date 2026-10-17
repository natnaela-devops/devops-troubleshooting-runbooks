# Oracle-to-Redis sync worker backpressure and connection exhaustion

This runbook documents a real Python data-sync incident where a containerized worker mirrored records from Oracle into Redis but became unstable during spikes because it opened too many short-lived database and Redis connections.

## Symptoms

- Worker crashes or disconnects during bursts.
- Latency increases as record volume rises.
- Oracle connection pools starve or socket usage grows rapidly.
- Redis writes become dominated by network round-trips.

## Root cause

The worker treated each record as an isolated network transaction. Creating fresh Oracle/Redis connections and issuing individual Redis writes multiplied TCP setup cost, increased socket pressure, and reduced throughput until the worker could not keep up with incoming work.

## Remediation used

### Reuse Oracle sessions

The worker was refactored to use an Oracle session pool instead of opening a database connection for every record.

Conceptually:

```python
pool = cx_Oracle.SessionPool(
    user=DB_USER,
    password=DB_PASSWORD,
    dsn=DB_DSN,
    min=2,
    max=10,
    increment=1,
    threaded=True,
)

with pool.acquire() as conn:
    # query/process records
    pass
```

Pool sizing must match actual database capacity and workload; the numbers above are illustrative.

### Reuse Redis connections

```python
redis_pool = redis.ConnectionPool(
    host=REDIS_HOST,
    port=REDIS_PORT,
    password=REDIS_PASSWORD,
)
client = redis.Redis(connection_pool=redis_pool)
```

### Batch Redis writes

Instead of one network round-trip per key, writes were grouped with `pipeline()` and executed in batches. The incident used batches on the order of 1,000 records where appropriate.

```python
pipe = client.pipeline(transaction=False)
for key, value in batch:
    pipe.set(key, value)
pipe.execute()
```

### Back off on transient failures

Retries used exponential backoff rather than immediate tight-loop retries so temporary network or database contention did not create a retry storm.

## Validation

Compare before/after behavior using:

- records processed per second;
- active Oracle sessions;
- Redis connection count;
- error/retry rate;
- batch execution latency;
- worker memory and CPU;
- queue/backlog depth.

## Lesson

High-volume integration workers need explicit backpressure behavior. Connection pooling, batching, bounded concurrency, and paced retries are capacity controls, not just performance optimizations.