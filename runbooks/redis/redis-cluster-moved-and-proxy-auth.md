# Redis Cluster `MOVED` Errors and Proxy Authentication Troubleshooting

This runbook covers two related Redis Cluster issues: applications receiving `MOVED` responses because they are not cluster-aware, and confusing authentication behavior when a proxy such as Predixy sits in front of the cluster.

## 1. Understand `MOVED`

Example:

```text
MOVED 1234 10.0.0.20:7001
```

This is not a random failure. The contacted Redis node is telling the client which node owns the requested hash slot.

A non-cluster-aware client connected directly to one Redis port may fail as soon as a key belongs to another node.

## 2. Check cluster health

```bash
redis-cli -h <redis-host> -p 7000 cluster info
redis-cli -h <redis-host> -p 7000 cluster nodes
```

Expected:

```text
cluster_state:ok
cluster_slots_assigned:16384
```

## 3. Test with a cluster-aware CLI

```bash
redis-cli -c -h <redis-host> -p 7000
```

The `-c` option follows cluster redirections automatically.

## 4. Proxy pattern

A Redis Cluster proxy can expose one application-facing port while following Redis Cluster redirects internally.

Typical pattern:

```text
Application
    |
    v
Predixy :7100
    |
    +--> Redis Cluster node :7000
    +--> Redis Cluster node :7001
    +--> other masters/replicas
```

The application must point to the proxy port, not a Kubernetes Service or firewall rule that exposes only one Redis Cluster node port.

## 5. Authentication design

Keep these questions separate:

1. Does Redis itself require authentication?
2. Does the proxy authenticate to Redis upstream?
3. Does the proxy require the application to authenticate to the proxy?

Do not assume configuring an upstream Redis password automatically makes the proxy reject unauthenticated downstream clients.

## 6. Validate authentication behavior explicitly

Test without authentication:

```bash
redis-cli -h <proxy-host> -p 7100 PING
```

Test with the expected password:

```bash
redis-cli -h <proxy-host> -p 7100 -a '<password>' PING
```

Test with an intentionally wrong password:

```bash
redis-cli -h <proxy-host> -p 7100 -a '<wrong-password>' PING
```

Do not consider authentication configured until all three behaviors match the intended design.

## 7. Spring Boot application variables

A typical application may use a secret-backed password and a single proxy endpoint:

```text
SPRING_DATA_REDIS_HOST=<proxy-host>
SPRING_DATA_REDIS_PORT=7100
SPRING_DATA_REDIS_PASSWORD=<secret>
```

Some Spring Boot versions and applications may use `spring.data.redis.*`, older `spring.redis.*`, or custom mappings. Confirm the application's effective configuration rather than setting both namespaces blindly.

## Common failure patterns

### Application sees `MOVED`

The application is bypassing the proxy or is using a non-cluster-aware client directly against a Redis Cluster node.

### Wrong password still appears to work

Check whether the proxy actually enforces downstream authentication. A proxy may accept an `AUTH` command without requiring it for subsequent commands, depending on its configuration.

### Only one Redis port is exposed

Redis Cluster redirects may point clients at another node or port. A single-port network abstraction is insufficient unless a cluster-aware proxy handles the redirects.
