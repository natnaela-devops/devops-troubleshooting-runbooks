# RCA: PostgreSQL logical decoding disabled — Flink CDC rule broadcaster fails

**Incident date:** 2026-10-19  
**Systems:** PostgreSQL 17, Apache Flink 1.20.3 (Kubernetes Application Mode), Debezium/PostgreSQL CDC, Apache Kafka  
**Severity:** Fraud-rule streaming impaired; precise business impact **not verified**  
**Status:** PostgreSQL configuration corrected and verified; end-to-end recovery **not yet verified**

> Public, sanitized technical case study. Hostnames, IP addresses, database/user names, registry URLs and credentials are omitted or replaced. Do not reuse production secrets in documentation.

## Executive summary

A Flink CDC job intended to propagate changes from a PostgreSQL fraud-rule table into Kafka was failing to create a logical replication slot. Its source logs reported:

```text
io.debezium.DebeziumException: Creation of replication slot failed
org.postgresql.util.PSQLException: ERROR: logical decoding requires "wal_level" >= "logical"
```

Direct database inspection confirmed PostgreSQL was running with `wal_level = replica`. PostgreSQL CDC using Debezium requires logical decoding, so the replication slot could not be created. A separate downstream Flink fraud-detection job reported Kafka topic metadata errors for the rules topic; the relationship is architecturally relevant, but the Kafka error's precise cause was **not proven** to be PostgreSQL alone.

The operator set `wal_level = logical` and subsequently verified that it was active with no restart pending. CDC replication-slot creation, rule messages reaching Kafka, and downstream job recovery were **not confirmed** in the evidence available for this RCA.

## Architecture and scope

```text
PostgreSQL (fraud-rule table)
    | logical decoding via Debezium / Flink CDC
    v
Flink rule broadcaster (source job)
    | publish rule events
    v
Kafka (rules topic)
    | consume rule updates
    v
Flink fraud-detection job
    | process transactions + dynamic rules
    v
Alert sinks
```

The jobs ran in Kubernetes and used a Kafka bootstrap service. The source job's logged settings identified a PostgreSQL CDC replication slot, a publication and the rules table.

## Symptoms / evidence

1. Flink and Java started; the source job was submitted, but logs indicated Debezium could not create its logical replication slot because PostgreSQL logical decoding was disabled.
2. SQL checks on the PostgreSQL primary returned:
   - `pg_is_in_recovery() = false`
   - `wal_level = replica` (before fix)
   - `max_replication_slots = 10`
   - `max_wal_senders = 10`
   - no existing replication slots
   - configured CDC publication existed and included the fraud-rule table
3. `ALTER SYSTEM SET wal_level = 'logical';` returned `ALTER SYSTEM`, but the first subsequent `SHOW wal_level;` still reported `replica`.
4. `pg_file_settings` showed the new value in `postgresql.auto.conf` but `applied = false` / `setting could not be applied`; this is consistent with a postmaster setting that has not yet been activated.
5. Later verification returned `wal_level = logical` and `pending_restart = false`. The exact restart mechanism/time was **not captured** in the provided command output.
6. The other Flink job previously logged `Failed to get metadata for topics [fraud-rules]` and `UnknownTopicOrPartitionException`. Kafka topic existence, leaders and advertised listeners were **not verified**.

## Root cause

**Confirmed:** PostgreSQL was configured at `wal_level = replica`, which does not support the logical decoding required by this Debezium-based PostgreSQL CDC source. The replication slot creation therefore failed.

**Not established:** Why the required `wal_level` was absent originally (initial provisioning, drift, or a prior change), or whether the downstream Kafka metadata error was caused by a missing topic, broken partition leadership, or broker-side metadata/listener configuration.

## Remediation performed

```sql
-- Verified primary versus standby:
SELECT pg_is_in_recovery();

-- Captured pre-change settings:
SHOW wal_level;
SHOW max_replication_slots;
SHOW max_wal_senders;

SELECT slot_name, slot_type, active
FROM pg_replication_slots;

SELECT pubname, schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'dbz_publication';

-- Applied via an administrator:
ALTER SYSTEM SET wal_level = 'logical';

-- Final verified state:
SHOW wal_level;
SELECT name, setting, pending_restart
FROM pg_settings
WHERE name = 'wal_level';
-- wal_level = logical; pending_restart = false
```

`wal_level` requires a PostgreSQL server restart to activate. Any such restart should be coordinated according to database HA and maintenance policy. A configuration reload alone cannot activate this setting. The exact restart command executed is not captured by the evidence and is not represented as confirmed work.

The preexisting replication-slot and WAL sender limits were not modified, as they were already set to 10.

## Verification / remaining work

| Check | Evidence-based result |
| --- | --- |
| PostgreSQL primary | Confirmed |
| CDC publication includes rule table | Confirmed |
| `wal_level = logical` active | Confirmed |
| `pending_restart = false` | Confirmed |
| Debezium slot created and active | **Pending verification** |
| CDC reads database changes | **Pending verification** |
| Kafka rules topic exists / partitions have leaders | **Pending verification** |
| Fraud-detection Flink job stable | **Pending verification** |
| End-to-end rule propagation | **Pending verification** |

Suggested read-only checks:

```sql
SELECT slot_name, slot_type, plugin, active,
       restart_lsn, confirmed_flush_lsn
FROM pg_replication_slots;
```

```bash
kubectl -n taf-flink get flinkdeployments,pods
# Inspect the actual JobManager and TaskManager logs for both applications.
# From an authorized Kafka broker/container, describe the rules topic:
kafka-topics.sh --bootstrap-server '<bootstrap-service>:9092' --describe --topic fraud-rules
```

Test a controlled, authorized fraud-rule update and verify it is emitted to Kafka and received by the consuming job. Do not create or delete Kafka topics or replication slots blindly: inspect their ownership and existing state first.

## Preventive actions

- Add PostgreSQL CDC preflight validation: `wal_level`, replication privileges, publication membership, free replication slots, WAL sender capacity, network connectivity, and topic metadata.
- Treat server-parameter changes as managed configuration with maintenance/restart approval and post-restart verification.
- Alert on Flink job restarts, source exceptions, Kafka topic/partition availability, consumer lag, and CDC slot inactivity / retained WAL.
- Use durable, appropriate Flink checkpoint storage and validate state recovery in controlled tests rather than relying solely on JobManager-local checkpoint data.
- **Security finding:** The incident logs displayed the PostgreSQL password in Flink program arguments and startup output. Rotate the exposed credential, scrub retained logs where policy permits, and supply credentials through approved secret handling without logging them.
- Investigate the separate `flink-conf.yaml: Read-only file system` startup warning. The job continued startup, so that message was not established as the CDC root cause.

## Lessons learned

A running Flink JobManager or initially RUNNING job does not prove that PostgreSQL CDC is healthy. Validate each edge independently: PostgreSQL logical replication → Flink source → Kafka topic → consuming Flink job. Separate confirmed causes from plausible downstream effects, and do not label end-to-end recovery complete without data-plane verification.
