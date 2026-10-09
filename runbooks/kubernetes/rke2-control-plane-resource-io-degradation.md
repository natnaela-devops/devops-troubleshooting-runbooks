# RKE2 Control-Plane Degradation from Resource or Disk I/O Pressure

This runbook covers an RKE2 control-plane node that becomes slow or unstable during high CPU, memory, or disk I/O pressure.

## Symptoms

- `kubectl` commands become slow or time out
- etcd/control-plane components restart or become unhealthy
- pods remain Pending/Unknown longer than expected
- node filesystem usage or I/O latency is high
- Longhorn or application storage workloads amplify disk contention

## 1. Check node pressure first

```bash
uptime
free -h
df -h
df -i
vmstat 1 10
iostat -xz 1 5 2>/dev/null || true
```

Do not restart RKE2 immediately if the node is saturated; identify whether the root cause is capacity or I/O contention first.

## 2. Inspect RKE2 and kubelet state

```bash
systemctl status rke2-server --no-pager
journalctl -u rke2-server -n 300 --no-pager
kubectl get nodes -o wide
kubectl get pods -A -o wide | grep -Ev 'Running|Completed'
```

## 3. Check etcd health

Use the RKE2-provided tooling/certificates appropriate for the installed release. At minimum, inspect control-plane logs for etcd leader changes, slow requests, fsync latency, or quorum errors.

```bash
journalctl -u rke2-server --since '-30 min' | grep -Ei 'etcd|leader|quorum|slow|fsync|timeout'
```

## 4. Find high-storage workloads

```bash
kubectl get pods -A -o wide
kubectl get pvc -A
kubectl get pv
```

If Longhorn is installed:

```bash
kubectl -n longhorn-system get pods
kubectl -n longhorn-system get nodes.longhorn.io
```

## 5. Recover safely

Prefer relieving the resource bottleneck over restarting the entire control plane. Examples include:

- free disk space without deleting Kubernetes data blindly
- stop or reschedule a runaway non-control-plane workload
- correct a logging process consuming the root filesystem
- move application workloads away from control-plane-only nodes when architecture allows

## 6. Validate recovery

```bash
kubectl get nodes
kubectl get pods -A | grep -Ev 'Running|Completed'
journalctl -u rke2-server --since '-10 min' | grep -Ei 'error|timeout|etcd|slow'
```

A recovered API server is not enough; confirm etcd stability, node readiness, and storage health.
