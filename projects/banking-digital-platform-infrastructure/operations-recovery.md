# Operations, Troubleshooting, and Recovery

This document describes the operating principles used while supporting the banking platform across UAT and production.

## Core operating model

The platform combined clustered services, standalone services, Kubernetes workloads, reverse proxies, identity services, databases, storage, messaging, caching, and observability. Troubleshooting therefore focused on identifying the failing layer before changing configuration.

## Investigation sequence

A common sequence was:

```text
symptom
  |
  v
network / DNS / TLS
  |
  v
service process and listener
  |
  v
runtime configuration
  |
  v
dependency health
  |
  v
application behavior
  |
  v
business-flow verification
```

Examples of this approach included:

- separating Kafka quorum health from Java client configuration failures
- distinguishing Redis Cluster redirects from service exposure/proxy behavior
- confirming mounted Kubernetes Secret files before blaming certificate generation
- checking database migration history before treating a schema problem as an infrastructure failure
- distinguishing a healthy Nginx process from a working upstream application route

## Change safety

Before high-impact changes:

- back up current configuration
- capture the current healthy state
- define rollback steps
- prefer rolling changes for clustered systems
- validate health between nodes/steps
- avoid changing multiple independent layers at the same time unless required

## Clustered-service checks

### Kafka

- quorum voters and leader state
- follower lag
- listener availability
- TLS/authentication behavior
- producer/consumer runtime behavior

### Redis

- cluster state
- slot ownership
- master/replica topology
- Predixy path
- application authentication

### RKE2

- node readiness
- control-plane/etcd health
- workload rollout status
- storage/PVC state
- image-pull and Secret/configuration state

### YugabyteDB

- service/cluster readiness
- YSQL availability
- application connectivity
- migration/schema state

## Recovery boundaries

Recovery actions were chosen based on the failing component rather than applying broad restarts.

Examples:

- a client-side Kafka property conflict should be fixed in the application rather than restarting healthy brokers
- a malformed or double-encoded Kubernetes Secret should be corrected at the Secret/mount layer rather than reissuing valid certificates
- a full filesystem should be investigated for the actual space consumer before deleting data
- a database startup or readiness problem should be separated from application migration failures

## Verification after recovery

A fix was considered complete only after the affected service demonstrated the expected behavior. Verification could include:

- service/systemd state
- listening sockets
- cluster/quorum/replication state
- logs
- metrics
- direct protocol tests
- application runtime configuration
- producer/consumer or database connectivity
- business-flow confirmation

## Documentation discipline

Public documentation records the troubleshooting method and lessons learned but removes all sensitive banking details. Where evidence did not prove a root cause, the runbook should say that explicitly rather than inventing a resolution.
