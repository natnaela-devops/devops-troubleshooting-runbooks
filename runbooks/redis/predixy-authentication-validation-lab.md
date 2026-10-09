# Predixy Authentication Validation in an Isolated Redis Cluster Lab

## Problem

A Redis Cluster proxy appears to accept commands even when authentication behavior does not match expectations. A bad `AUTH` attempt may produce an error while later commands still succeed, making it unclear whether the proxy is actually enforcing client authentication.

## Why reproduce this in a lab

Do not experiment with authentication semantics directly on a production Redis Cluster. Build a disposable cluster that reproduces the proxy path first.

A useful lab topology is six Redis containers: three masters and three replicas, plus one Predixy container.

## Confirm Redis Cluster health

```bash
redis-cli -h <redis-node> -p <port> cluster info
redis-cli -h <redis-node> -p <port> cluster nodes
```

Expected indicators include:

```text
cluster_state:ok
cluster_slots_assigned:16384
```

## Establish the baseline

Test the proxy without authentication:

```bash
redis-cli -h 127.0.0.1 -p <predixy-port> PING
```

Then test a deliberately incorrect credential:

```bash
redis-cli -h 127.0.0.1 -p <predixy-port> AUTH wrong-password
redis-cli -h 127.0.0.1 -p <predixy-port> PING
```

Do not interpret an `AUTH` error alone as proof that subsequent commands are blocked. Test the command path explicitly.

## Inspect the actual Predixy configuration

Verify which configuration is mounted into the running container:

```bash
docker inspect predixy
docker exec predixy sh -c 'pwd; find / -maxdepth 4 -type f -name "*.conf" 2>/dev/null'
```

A common failure mode is editing an `auth.conf` on the host that is not the file Predixy actually loads.

## Enforce one intended authority

Configure the minimum authority model required by the application. If only one administrator credential is intended, avoid adding multiple roles merely to make the test pass.

Restart the proxy after configuration changes:

```bash
docker restart predixy
docker logs --tail=200 predixy
```

## Positive and negative tests

Unauthenticated client:

```bash
redis-cli -h 127.0.0.1 -p <predixy-port> PING
```

Expected: rejected when authentication is enforced.

Wrong credential:

```bash
redis-cli -h 127.0.0.1 -p <predixy-port> --no-auth-warning -a wrong-password PING
```

Expected: rejected.

Correct credential:

```bash
redis-cli -h 127.0.0.1 -p <predixy-port> --no-auth-warning -a '<password>' PING
```

Expected:

```text
PONG
```

## Lesson

Authentication must be validated with both positive and negative command tests. A proxy logging an authentication error is not sufficient evidence that unauthenticated traffic is blocked.