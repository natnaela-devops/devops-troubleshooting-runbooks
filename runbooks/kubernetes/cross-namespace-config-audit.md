# Cross-Namespace Kubernetes Configuration Audit

## Problem

The same dependency endpoint is copied into multiple ConfigMaps or Deployments across namespaces. After an IP, port, hostname, registry project, or backend endpoint changes, some workloads are updated while others continue using stale values.

## Symptoms

- Only some services recover after a dependency migration.
- Different namespaces point to different Redis, API, database, or Kafka endpoints.
- Restarting one deployment appears to fix the problem only partially.
- A configuration change was applied successfully but another application continues failing.

## Investigation

Search ConfigMaps across all namespaces:

```bash
kubectl get configmap -A -o json | jq -r '.items[] | [.metadata.namespace,.metadata.name,((.data // {})|tostring)] | @tsv' | grep -Ei '<old-host>|<old-ip>|REDIS|KAFKA|DATABASE|API'
```

Search Deployments for environment variables and literal values:

```bash
kubectl get deploy -A -o json | jq -r '.items[] | [.metadata.namespace,.metadata.name,((.spec.template.spec.containers // [])|tostring)] | @tsv' | grep -Ei '<old-host>|<old-ip>|REDIS|KAFKA|DATABASE|API'
```

Search Secrets only by metadata unless you have a specific operational reason to inspect decoded content:

```bash
kubectl get secret -A
```

Inspect one affected workload:

```bash
kubectl -n <namespace> get deploy <deployment> -o yaml
kubectl -n <namespace> get configmap <configmap> -o yaml
kubectl -n <namespace> describe pod <pod>
```

## Safe update pattern

Back up the existing object:

```bash
kubectl -n <namespace> get configmap <name> -o yaml > <name>.before.yaml
```

Patch only the intended keys:

```bash
kubectl -n <namespace> patch configmap <name> --type merge -p '{"data":{"REDIS_HOST":"<new-host>","REDIS_PORT":"<new-port>"}}'
```

Repeat deliberately for every consumer rather than assuming configuration is shared automatically.

## Apply the new configuration

A ConfigMap update does not guarantee an already-running process reloads the value. If the application reads environment variables only at startup, restart the workload safely:

```bash
kubectl -n <namespace> rollout restart deployment/<deployment>
kubectl -n <namespace> rollout status deployment/<deployment>
```

## Verification

```bash
kubectl -n <namespace> get configmap <name> -o json | jq '.data'
kubectl -n <namespace> get pods -o wide
kubectl -n <namespace> logs deploy/<deployment> --tail=200
```

Then run the cluster-wide search again for the old endpoint.

## Lesson

Treat an endpoint migration as a dependency inventory problem, not a single-Deployment edit. Search the entire cluster for stale references before declaring the change complete.
