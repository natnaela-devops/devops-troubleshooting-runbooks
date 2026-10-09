# Discover Nonstandard systemd Services and Runtime Configuration

## Problem

A familiar service name does not exist:

```bash
systemctl status redis
```

returns `Unit redis.service could not be found`, even though Redis processes are clearly running.

This commonly happens when software is deployed as multiple custom systemd units rather than from a distribution package.

## Find the real units

```bash
systemctl list-units --type=service --all | grep -Ei 'redis|predixy|java|nginx|kafka'
systemctl list-unit-files | grep -Ei 'redis|predixy'
```

Then inspect each candidate:

```bash
systemctl status <unit>
systemctl cat <unit>
```

## Inspect running processes

```bash
ps -ef | grep -Ei '[r]edis|[p]redixy'
pgrep -a redis-server
```

The process command line often reveals the real port and configuration path.

## Inspect listening ports

```bash
ss -lntp
ss -lntp | grep -E ':<port1>|:<port2>'
```

A multi-instance Redis host may legitimately have separate processes on different ports, each with a separate unit and config.

## Locate configuration safely

Prefer evidence from the unit and process command line before searching the whole filesystem:

```bash
systemctl cat <unit>
ps -ef | grep '<process-name>'
```

If needed:

```bash
find /etc /opt -maxdepth 5 -type f \( -name '*.conf' -o -name '*.service' \) 2>/dev/null | grep -Ei 'redis|predixy'
```

## Follow logs

```bash
journalctl -u <unit> -n 200 --no-pager
journalctl -u <unit> -f
```

## Lesson

Do not assume the package-default service name or `/etc/<service>` layout. Discover the unit, process arguments, listening sockets, and loaded configuration before changing anything.