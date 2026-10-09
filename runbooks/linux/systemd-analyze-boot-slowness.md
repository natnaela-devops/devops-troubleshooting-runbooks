# Diagnose Linux boot slowness with systemd-analyze

## Problem
A Linux workstation felt unusually slow during boot, but there was no single obvious failing service.

## Investigation
Measure before disabling anything:

```bash
systemd-analyze
systemd-analyze blame
systemd-analyze critical-chain
```

These commands separate firmware, bootloader, kernel, userspace, and service startup time.

A common pattern is that `NetworkManager-wait-online.service` delays services that declare a dependency on `network-online.target`, with Docker or other network-dependent services starting afterward.

Inspect only the services on the critical path:

```bash
systemctl status NetworkManager-wait-online.service --no-pager
systemctl list-dependencies --reverse network-online.target
journalctl -b -u NetworkManager-wait-online.service
```

If graphics/driver symptoms are also suspected, inspect kernel logs independently:

```bash
dmesg | grep -Ei 'nvidia|drm|gpu|error|fail|timeout'
journalctl -k -b | grep -Ei 'nvidia|drm|gpu|error|fail|timeout'
```

## Shell pitfall
Do not assume aliases behave like GNU `grep`. If `grep` has been aliased to another tool, complex flags may produce misleading errors. Verify with:

```bash
type grep
command grep -Ei 'pattern'
```

## Decision rule
Do not disable `NetworkManager-wait-online` simply because it appears near the top of `blame`. First confirm whether services genuinely require full online connectivity at boot.

## Verification
After any change, compare a fresh boot using the same three `systemd-analyze` commands.

## Lesson
Boot optimization is dependency analysis, not a race to disable the slowest-looking unit. `critical-chain` is often more useful than `blame` because it shows what actually delayed the boot target.