# RKE2 Production Features and Hardening Guide

RKE2 provides more than a Kubernetes control plane. A production deployment should deliberately use the platform features that improve recovery, isolation, security, and operability.

This guide focuses on features worth planning for private infrastructure and regulated environments.

## 1. Embedded etcd HA and snapshots

For a three-server control plane, embedded etcd provides quorum-based cluster state storage.

Do not treat a running three-member etcd cluster as a backup strategy. Configure scheduled snapshots and keep copies outside the same failure domain as the cluster.

Example configuration concept:

```yaml
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 20
```

Operational requirements:

- test restore procedures before an incident
- keep off-cluster snapshot copies
- verify snapshot age and retention
- never restart or reset all etcd members simultaneously

## 2. Secrets encryption at rest

Kubernetes Secrets stored in etcd should be protected with encryption at rest where required by the security model.

Check RKE2 secrets-encryption state with the commands supported by the installed version, for example:

```bash
rke2 secrets-encrypt status
```

Key rotation should be planned and tested rather than performed ad hoc during an incident.

## 3. Separate control plane and workers

Small clusters often run workloads on the same machines as etcd and the control plane:

```text
node-1 -> control-plane + etcd + applications
node-2 -> control-plane + etcd + applications
node-3 -> control-plane + etcd + applications
```

For production, a stronger design is:

```text
cp-1 -> control-plane + etcd
cp-2 -> control-plane + etcd
cp-3 -> control-plane + etcd

worker-1 -> applications
worker-2 -> applications
worker-3 -> applications
```

This reduces the chance that application CPU, memory, or disk pressure destabilizes etcd.

## 4. Taints, labels, affinity, and topology spread

Do not let important workloads land randomly.

Use labels to express node roles or capabilities:

```text
storage=true
monitoring=true
database=true
dmz=true
```

Use taints to keep ordinary applications off infrastructure nodes, and tolerations only where required.

Use pod anti-affinity or topology spread constraints for replicated services so multiple replicas are not concentrated on the same node.

Example desired placement:

```text
keycloak-0 -> worker-1
keycloak-1 -> worker-2
keycloak-2 -> worker-3
```

## 5. PodDisruptionBudgets

A PodDisruptionBudget protects availability during voluntary disruptions such as node drain and maintenance.

For a three-replica service, a common policy is:

```text
minAvailable: 2
```

A PDB does not protect against an unexpected node crash, but it prevents maintenance automation from voluntarily evicting too many replicas at once.

## 6. Resource requests and limits

Every production workload should have reviewed resource requests. Limits should be applied deliberately rather than copied blindly.

Example:

```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: "1"
    memory: 1Gi
```

Requests drive scheduling decisions. Poor or missing requests can produce node overcommit and unpredictable placement.

## 7. PriorityClasses

PriorityClasses allow critical workloads to receive preference during resource pressure.

Useful categories may include:

```text
cluster infrastructure
critical gateway/API
normal application
batch/background work
```

Priority should be rare and intentional; marking every workload as critical defeats the mechanism.

## 8. Startup, readiness, and liveness probes

The probes answer different questions:

```text
startupProbe  -> has the application finished starting?
readinessProbe -> should it receive traffic now?
livenessProbe -> is the process unhealthy enough to restart?
```

Bad probe design can turn a slow dependency or storage event into a restart loop.

Tune probes from observed application startup and recovery behavior, not arbitrary defaults.

## 9. Rolling update strategy and graceful termination

For critical stateless services, consider zero voluntary unavailability during rolling deployment:

```yaml
strategy:
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

Applications should also handle termination correctly:

1. fail readiness
2. stop accepting new traffic
3. finish in-flight requests
4. close database/message-broker connections
5. exit before `terminationGracePeriodSeconds` expires

## 10. NetworkPolicy and CNI design

Kubernetes networking should not assume every pod can talk to every other pod.

Use NetworkPolicies to limit lateral movement and document required flows.

Example intent:

```text
payment-gateway -> required backend API
payment-gateway -> required Redis service
payment-gateway -X-> unrelated databases
payment-gateway -X-> Kubernetes API unless explicitly required
```

Evaluate the RKE2-supported CNI based on policy, observability, and operational requirements rather than trend alone.

## 11. Ingress, TLS, and certificates

Avoid exposing every HTTP application through arbitrary NodePorts when an ingress architecture is appropriate.

A common model is:

```text
external load balancer / VIP
          |
       ingress
       /  |  \
     API SSO Portal
```

Use cert-manager or an approved enterprise certificate workflow to manage TLS secrets. Keep hostname verification enabled and correct certificate SANs rather than disabling verification.

## 12. Private registries and air-gapped operation

RKE2 supports registry configuration through:

```text
/etc/rancher/rke2/registries.yaml
```

This can centralize:

- internal Harbor/registry endpoints
- registry authentication
- custom CA trust
- image mirrors

For restricted environments, plan image synchronization and upgrades before disconnecting the cluster from public registries.

## 13. Audit logging

Kubernetes API audit logs are valuable for operational and security investigations.

Questions audit logging can answer include:

```text
Who deleted this deployment?
Who changed this Secret?
Who patched this Service?
Which identity created a privileged pod?
```

Define retention, access, and forwarding requirements before enabling high-volume audit policies in production.

## 14. RBAC and ServiceAccounts

Avoid using `cluster-admin` for routine human and application access.

Design roles such as:

```text
platform administrator
DevOps operator
developer viewer
application support
security/audit viewer
```

Applications should use dedicated ServiceAccounts with only the Kubernetes API permissions they actually require.

## 15. Pod Security and admission controls

Restrict dangerous pod settings unless a workload has an approved need for them:

```text
privileged: true
hostNetwork: true
hostPID: true
hostPath mounts
running as root
```

Admission controls reduce the chance that one application becomes equivalent to root access on a Kubernetes node.

## 16. Storage strategy

Do not force every workload onto the same storage backend.

A cluster may deliberately use:

```text
emptyDir -> temporary data
local storage -> distributed databases/message brokers with application replication
Longhorn -> general replicated PVCs
external CSI -> enterprise storage
```

Keep RKE2/etcd storage isolated from heavy application storage where possible.

## 17. Autoscaling

Horizontal Pod Autoscaling can increase replica count when a service genuinely scales horizontally and appropriate metrics exist.

Before enabling HPA, confirm:

- resource requests are accurate
- the service is stateless or state is externalized
- downstream dependencies can handle the extra concurrency
- minimum replica count meets availability requirements

Autoscaling an already overloaded database dependency can make an incident worse.

## 18. Controlled upgrades

Do not upgrade all control-plane nodes at once.

A safer pattern is:

```text
1. verify backups/snapshots
2. verify current cluster health
3. upgrade one control-plane node
4. validate
5. continue one node at a time
6. upgrade workers in controlled batches
7. perform post-upgrade validation
```

Read the RKE2 release notes and Kubernetes version-skew requirements for the exact target version.

## 19. Baseline health checks

Useful post-change checks include:

```bash
kubectl get nodes -o wide
kubectl get pods -A | grep -Ev 'Running|Completed'
kubectl get --raw='/readyz?verbose'
systemctl status rke2-server --no-pager
cat /proc/pressure/io
iostat -xz 1 3
```

If Longhorn is installed:

```bash
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get nodes.longhorn.io -n longhorn-system
```

## Recommended learning order

For engineers moving from Kubernetes operations toward platform/SRE design, learn these areas deeply:

1. etcd backup, restore, quorum, and disaster recovery
2. scheduling: requests, limits, affinity, taints, topology spread, PDBs
3. CNI and NetworkPolicy
4. pod lifecycle: probes, shutdown, rollout behavior
5. RBAC, audit logging, secrets encryption, and Pod Security
6. storage failure domains and CSI architecture
7. monitoring, alerting, and capacity planning

The goal is not to enable every feature. The goal is to understand which failure mode each feature addresses and make the cluster design intentional.