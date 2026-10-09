# OpenSearch Timestamp-Field Validation for Ingested Events

## Problem

Events exist in an OpenSearch index but timelines, Discover views, or range queries are unreliable because it is unclear which source field contains the real event time.

## Inspect document count

```bash
curl -sS '<opensearch-url>/<index>/_count' | jq
```

## Check timestamp-field presence

Rather than guessing from mappings alone, count how many documents actually contain each candidate field.

Candidates often include:

```text
createdAt
occurredAt
timestamp
eventTimestamp
@timestamp
```

Example aggregation/query approach:

```bash
curl -sS -H 'Content-Type: application/json' '<opensearch-url>/<index>/_search' -d '{
  "size": 0,
  "aggs": {
    "createdAt": {"filter": {"exists": {"field": "createdAt"}}},
    "occurredAt": {"filter": {"exists": {"field": "occurredAt"}}},
    "timestamp": {"filter": {"exists": {"field": "timestamp"}}}
  }
}' | jq
```

## Sample actual values

```bash
curl -sS -H 'Content-Type: application/json' '<opensearch-url>/<index>/_search' -d '{
  "size": 10,
  "_source": ["createdAt","occurredAt","timestamp","eventTimestamp","@timestamp"],
  "sort": [{"_doc":"asc"}]
}' | jq
```

## Validate mapping

```bash
curl -sS '<opensearch-url>/<index>/_mapping' | jq
```

The field chosen for time filtering should be mapped as a usable date type, not merely stored as arbitrary text.

## Fix strategy

If the source event time is present but not mapped to the field used by dashboards, correct the ingest pipeline or index template for future data. Reindex historical data only after validating the transformation on a small sample.

## Lesson

Do not choose a timestamp because its name looks correct. Verify field presence, actual values, mapping type, and semantic meaning against the source event.