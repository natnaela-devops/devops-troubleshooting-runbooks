# Redis Cluster and Predixy Architecture

This document explains a common Redis Cluster architecture where applications connect through Predixy while Redis itself provides clustered data placement and replication.

## Core topology

A typical layout is:

```text
Application
    |
    v
Predixy
    |
    +-----------------------------+
    |              |              |
    v              v              v
Redis master A  Redis master B  Redis master C
    |              |              |
    v              v              v
Replica A        Replica B        Replica C
```

Redis Cluster divides the keyspace into 16,384 hash slots. The masters own different slot ranges, while replicas provide redundancy for their corresponding masters.

## Why a proxy is useful

Without a cluster-aware proxy, a client that connects to the wrong Redis node can receive a redirect such as:

```text
MOVED <slot> <host:port>
```

A cluster-aware client can follow that redirect itself. Predixy can instead provide a stable endpoint and route requests to the correct Redis node.

```text
Application
    |
    | one Redis endpoint
    v
Predixy
    |
    | cluster topology / routing
    v
correct Redis master
```

Predixy is therefore part of the request path. This differs from Kafka bootstrap servers, which are discovery seeds rather than proxies.

## Redis process model

One physical host may run more than one Redis instance, for example:

```text
redis-server :7000
redis-server :7001
```

Each instance has its own configuration, data path, node identity, and cluster-bus port.

For example:

```text
client port 7000 -> cluster bus 17000
client port 7001 -> cluster bus 17001
```

The exact ports are environment-specific.

## Authentication flow

A practical authenticated design is:

```text
Application
    |
    | Redis credential from secret/configuration
    v
Predixy
    |
    | connects to the Redis Cluster using the required Redis authentication
    v
Redis masters / replicas
```

Do not add an unrelated second proxy-authentication layer unless the architecture actually requires it. Keep the authentication model understandable and test it with real application behavior.

## Validation sequence

Validate each layer separately.

### 1. Redis processes

Confirm every expected Redis instance is running and listening.

```bash
systemctl status redis-7000 redis-7001
ss -lntp | grep -E ':(7000|7001)\b'
```

### 2. Cluster health

Use a cluster-aware Redis CLI and verify:

```text
cluster_state:ok
cluster_known_nodes: expected count
cluster_size: expected master count
all 16384 slots assigned
```

A six-instance design commonly uses three masters and three replicas.

### 3. Direct authenticated Redis access

Test authentication against the Redis layer independently from Predixy.

The purpose is to prove that Redis itself accepts the intended credential before introducing the proxy into the test.

### 4. Predixy

Confirm the proxy is running and listening:

```bash
systemctl status predixy
ss -lntp | grep ':7100\b'
```

Then test through the proxy using the same client behavior expected from the application.

### 5. Application path

Finally validate:

```text
application -> Predixy -> Redis Cluster -> response
```

A successful `PING` is useful but does not prove the complete application flow. Also test representative reads and writes.

## Common failure: MOVED errors leak to the application

If an application receives `MOVED` responses unexpectedly, investigate:

- whether it bypassed Predixy and connected directly to a Redis node
- whether the Kubernetes Service exposes only one Redis instance instead of a cluster-aware endpoint
- whether the client library is configured for standalone Redis when it should be cluster-aware
- whether Predixy discovered the complete cluster topology

## Common failure: confusing authentication results

If a test appears to show both an authentication error and a successful command, reproduce the behavior locally with the same Redis and Predixy configuration before changing production authentication.

Check:

- where authentication is enforced
- whether Predixy has an `Authority` rule
- whether Redis itself requires authentication
- whether the client sends `AUTH`
- whether a test command is actually reaching the intended endpoint

Do not infer the final authentication design from one ambiguous CLI response.

## Application secret handling

For Kubernetes applications, keep the Redis password in a Secret and expose only the required key to the workload.

Example conceptual configuration:

```text
REDIS_HOST=<proxy endpoint>
REDIS_PORT=<proxy port>
REDIS_PASSWORD=<from Kubernetes Secret>
```

Never commit real Redis passwords or private network addresses to a public repository.

## Readiness criteria

The Redis path is ready when:

- all expected Redis instances are running
- the cluster reports `cluster_state:ok`
- all 16,384 slots are assigned
- the expected master/replica topology is healthy
- authenticated direct Redis access behaves as designed
- Predixy is healthy and can route requests across the cluster
- the application can read and write through the intended endpoint
- no unexplained `MOVED` or authentication errors remain

## Operational boundary

Predixy does not replace Redis Cluster replication or failover behavior. It provides a stable, cluster-aware access layer. Redis Cluster remains responsible for slot ownership, replication relationships, and node topology.
