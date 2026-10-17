# OpenSearch storage exhaustion, write blocks, and unassigned shards

This runbook documents a real OpenSearch incident where daily index growth pushed disk usage past watermark thresholds, the cluster moved into yellow/red health, and shard allocation/write behavior degraded.

## Symptoms

- Cluster health becomes `yellow` or `red`.
- Shards remain unassigned.
- Disk utilization exceeds high-watermark thresholds.
- Writes fail or indices become blocked.
- Log indices continue growing without lifecycle cleanup.

## Root cause

Daily indices accumulated without an automated retention policy. Disk pressure then interacted with shard allocation rules. At the same time, overly broad mappings caused fields that did not need full-text indexing—such as raw stack traces or other high-cardinality strings—to consume additional storage and heap.

## Immediate triage

Check cluster health, allocation, disk usage, and index size before deleting anything:

```bash
curl -sS -k -u '<user>:<password>' https://localhost:9200/_cluster/health?pretty
curl -sS -k -u '<user>:<password>' https://localhost:9200/_cat/allocation?v
curl -sS -k -u '<user>:<password>' https://localhost:9200/_cat/indices?v&s=store.size:desc
curl -sS -k -u '<user>:<password>' https://localhost:9200/_cluster/allocation/explain?pretty
```

## Long-term remediation used

### Apply Index State Management

A lifecycle policy was introduced so indices rolled over and eventually expired instead of growing forever.

Sanitized example:

```json
{
  "policy": {
    "description": "30-day log lifecycle policy",
    "default_state": "hot",
    "states": [
      {
        "name": "hot",
        "actions": [
          { "rollover": { "min_index_age": "7d", "min_primary_shard_size": "30gb" } }
        ],
        "transitions": [
          { "state_name": "delete", "conditions": { "min_index_age": "30d" } }
        ]
      },
      {
        "name": "delete",
        "actions": [ { "delete": {} } ]
      }
    ]
  }
}
```

Retention, rollover age, and shard-size thresholds must be sized from actual ingest rate and storage capacity.

### Standardize index templates

Separate application and platform index patterns were given explicit mappings instead of allowing every string field to be indexed indiscriminately. Fields such as raw stack traces were kept searchable only where needed, while identifiers/timestamps were mapped deliberately.

## Recovery validation

After cleanup/lifecycle changes:

1. confirm disk headroom is restored;
2. verify write blocks are cleared only after the underlying disk condition is fixed;
3. check that previously unassigned shards allocate;
4. confirm new indices inherit the intended template and ISM policy;
5. monitor shard count and daily storage growth.

## Lesson

Deleting old indices during an outage fixes capacity only temporarily. Sustainable OpenSearch operations require retention, rollover, mapping discipline, and shard sizing to be designed together.