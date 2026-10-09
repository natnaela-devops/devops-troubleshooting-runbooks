# Redis Cluster `MOVED` Errors Behind Kubernetes Services

## Problem

An application connects successfully to a Redis Cluster endpoint exposed through Kubernetes, but commands fail with responses such as:

```text
MOVED <slot> <host>:<port>
```

The first Redis endpoint is reachable, but the cluster redirects the client to another Redis node or port that is not reachable through the Service design.

## Symptoms

- TCP connectivity to the configured Redis endpoint succeeds.
- Simple tests may work against one node.
- Cluster-aware operations return `MOVED` redirects.
- The redirected port is not exposed by the Kubernetes Service or is unreachable from the application network.
- Application logs show Redis connection errors even though the original endpoint is healthy.

## Investigation

Inspect the application configuration first:

```bash
kubectl -n <namespace> get deploy <deployment> -o yaml | grep -Ei 'REDIS|HOST|PORT'
```

Inspect Services and endpoints:

```bash
kubectl -n <namespace> get svc,endpoints -o wide
kubectl -n <namespace> describe svc <redis-service>
```

Check Redis cluster topology from a reachable node:

```bash
redis-cli -h <redis-host> -p <redis-port> cluster nodes
redis-cli -h <redis-host> -p <redis-port> cluster slots
```

Reproduce the client behavior:

```bash
redis-cli -c -h <redis-host> -p <redis-port> PING
```

The `-c` option makes `redis-cli` follow cluster redirects and exposes whether the advertised targets are actually reachable.

## Root cause pattern

Redis Cluster is not a single-endpoint protocol. A client can connect to one node and then be redirected to whichever node owns the requested hash slot. If only one Redis port is reachable, a redirected connection fails.

A Kubernetes Service that fronts only one Redis node does not automatically make all Redis Cluster-advertised addresses reachable.

## Resolution options

Choose one architecture intentionally:

1. Expose every Redis Cluster node/port that cluster-aware clients may be redirected to.
2. Configure cluster announcements so advertised addresses are reachable by the clients.
3. Use a compatible Redis Cluster proxy such as Predixy and point applications to the proxy.
4. Use a Kubernetes-aware Redis deployment pattern where advertised endpoints match the client network.

Do not "fix" the issue by repeatedly reconnecting only to the original node.

## Verification

```bash
redis-cli -c -h <reachable-endpoint> -p <port> SET runbook:test ok
redis-cli -c -h <reachable-endpoint> -p <port> GET runbook:test
redis-cli -c -h <reachable-endpoint> -p <port> DEL runbook:test
```

Then verify application logs no longer show `MOVED`, connection-refused, or timeout errors.

## Kubernetes configuration check

When an endpoint changes, inspect all namespaces that consume Redis rather than patching one deployment and assuming the migration is complete:

```bash
kubectl get configmap -A -o json | jq -r '.items[] | select((.data // {}) | tostring | test("REDIS"; "i")) | [.metadata.namespace,.metadata.name] | @tsv'
```

## Lesson

A successful connection to one Redis node proves transport reachability only. It does not prove that a Redis Cluster client can reach every node to which the cluster may redirect it.
