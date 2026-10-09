# Prometheus Retention vs Required History Window

## Problem

Dashboards or investigations require a longer history window than Prometheus is configured to retain. A query for 14 days, for example, cannot be validated reliably if local retention is only 5 days.

## Inspect the running configuration

Check the Prometheus systemd unit or process arguments:

```bash
systemctl cat prometheus
ps -ef | grep '[p]rometheus'
```

Look for flags such as:

```text
--storage.tsdb.retention.time=<duration>
--storage.tsdb.retention.size=<size>
```

## Understand the interaction

If both time and size retention limits are configured, the effective history can be shorter than the time value when the size limit is reached first.

A configured `14d` therefore does not guarantee 14 days of data if the storage cap is too small.

## Check actual oldest data

Use the Prometheus HTTP API or inspect representative series over the required time window. Do not validate retention from the startup flag alone.

Example API call:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query?query=<metric>' | jq
```

For a real historical check, use a range query covering the required period.

## Before increasing retention

Check disk capacity and TSDB growth:

```bash
df -hT
du -sh <prometheus-data-dir>
```

Estimate whether the node can safely hold the additional blocks.

## Verification

After changing retention and allowing enough time for new history to accumulate, confirm:

1. Prometheus starts with the intended flags.
2. Free disk remains healthy.
3. Required range queries return data across the expected window.
4. Compaction and WAL behavior remain normal in the logs.

## Lesson

A dashboard requirement such as “show 14 days” must be matched by the telemetry retention architecture. Query syntax cannot recover data that Prometheus has already deleted.