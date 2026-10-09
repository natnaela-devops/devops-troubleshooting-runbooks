# Repeated SMPP bind timeout: separate application retry behavior from network reachability

## Problem
An application repeatedly failed to bind to an SMPP endpoint. Each connection attempt timed out after roughly the configured socket/connect timeout, then retried on a fixed interval.

## Symptoms
- Repeated SMPP bind/connect failures.
- Timeout rather than authentication rejection.
- Predictable retry cadence in application logs.
- Application logging itself remained healthy, so the incident could be isolated from log-pipeline problems.

## Investigation
From the same host/network namespace as the application, test basic reachability first:

```bash
getent hosts <smpp-host>
nc -vz -w 10 <smpp-host> <smpp-port>
timeout 10 bash -c '</dev/tcp/<smpp-host>/<smpp-port>'
```

Inspect route and source interface:

```bash
ip route get <smpp-ip>
ip addr
ss -tnp | grep <smpp-port>
```

If a firewall is involved, capture enough evidence to distinguish SYN timeout from application-level rejection:

```bash
sudo tcpdump -ni any host <smpp-ip> and port <smpp-port>
```

## Diagnostic split
- `Connection refused`: target reachable, nothing accepting the port or active rejection.
- TCP connection succeeds but SMPP bind is rejected: investigate credentials/bind mode/system ID.
- TCP SYN retries until timeout: investigate routing, ACL/firewall, VPN, upstream service, or wrong endpoint.

## Verification
After network or endpoint correction, verify both:
1. TCP establishment succeeds quickly.
2. Application logs show a successful SMPP bind and stop entering the retry loop.

## Status
The original incident confirmed repeatable network-style timeouts; a final upstream/network fix was not captured. This runbook intentionally does not claim a resolved root cause.

## Lesson
A repeating client retry loop is not itself the root cause. Establish whether TCP connectivity fails before spending time rotating SMPP credentials or changing application retry settings.