# Linux: Root Filesystem Full Because of Docker JSON Logs

A common failure mode is a container using Docker's default `json-file` logging driver without rotation until `/var/lib/docker` fills the root filesystem.

## Symptoms

- `df -h /` reports `100%` usage.
- Services fail with `No space left on device`.
- Kafka or another database may fail while writing metadata/snapshots.

## 1. Confirm filesystem usage

```bash
df -hT
df -ih
```

## 2. Find large directories

```bash
du -xhd1 /var 2>/dev/null | sort -h
du -xhd1 /opt 2>/dev/null | sort -h
```

## 3. Find very large files

```bash
find /var /opt -xdev -type f -size +500M \
  -printf '%10s  %p\n' 2>/dev/null | sort -nr | head -30
```

## 4. Identify the container

If the large file is similar to:

```text
/var/lib/docker/containers/<container-id>/<container-id>-json.log
```

identify it:

```bash
docker ps -a --no-trunc | grep <container-id>
docker inspect -f '{{.Name}} | {{.Config.Image}} | {{.HostConfig.LogConfig.Type}}' <container-id>
```

## 5. Reclaim space without deleting the active log inode

For an active Docker `json-file` log:

```bash
truncate -s 0 /var/lib/docker/containers/<container-id>/<container-id>-json.log
sync
df -h /
```

Do not use this pattern on Kafka broker data directories or database storage.

## 6. Clean archived journal logs if needed

```bash
journalctl --disk-usage
journalctl --vacuum-size=500M
```

## 7. Clean old application logs separately

Preview first:

```bash
find /opt/kafka/logs -type f -mtime +14 -print | head -50
```

Calculate size:

```bash
find /opt/kafka/logs -type f -mtime +14 -print0 | \
  du --files0-from=- -ch 2>/dev/null | tail -1
```

Then remove if confirmed safe:

```bash
find /opt/kafka/logs -type f -mtime +14 -delete
```

Do not confuse Kafka application logs such as `/opt/kafka/logs` with broker data such as `/var/lib/kafka-logs`.

## 8. Configure Docker log rotation

Example `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  }
}
```

Remember: changing Docker daemon defaults generally applies to newly created containers. Existing containers may need to be recreated with the desired log configuration.
