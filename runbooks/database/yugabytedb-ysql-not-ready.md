# YugabyteDB YSQL Not Ready

This runbook covers a YugabyteDB node where the database process is running but YSQL remains `Not Ready`, often after resource pressure or PostgreSQL initialization/shared-memory problems.

## Start with process and service health

```bash
ps -ef | grep -Ei 'yb-master|yb-tserver|postgres' | grep -v grep
systemctl --failed
```

If YugabyteDB is containerized or managed by Kubernetes, inspect the pod/container logs instead of assuming a systemd unit exists.

## Check node and disk pressure

```bash
free -h
df -h
df -i
vmstat 1 5
```

Resource starvation and disk pressure can prevent the PostgreSQL layer from completing initialization even when other YugabyteDB components appear alive.

## Inspect YSQL/PostgreSQL initialization errors

Search the relevant YugabyteDB logs for:

```text
shared memory
postgres
initdb
FATAL
PANIC
No space left on device
```

Example:

```bash
grep -RniE 'shared memory|postgres|initdb|FATAL|PANIC|No space left' <yugabyte-log-dir> | tail -200
```

## Confirm readiness after remediation

Once the underlying initialization/resource issue is corrected, verify YSQL directly:

```bash
ysqlsh -h <host> -p 5433 -c 'select now();'
```

Then verify application connectivity and any schema migration history before declaring the node healthy.

## Important distinction

Do not treat `process exists` as equivalent to `database ready`. Validate the SQL endpoint, not only the daemon state.
