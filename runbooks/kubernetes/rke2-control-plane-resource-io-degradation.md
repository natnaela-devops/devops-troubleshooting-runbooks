# RKE2 Control-Plane Degradation from Disk I/O Pressure

This runbook documents a real failure pattern where an RKE2/Rancher cluster became unstable because severe storage latency affected the host filesystem, Longhorn, containerd, kubelet, and embedded etcd at the same time.

The goal is to distinguish a storage-driven control-plane failure from an etcd-only problem before taking destructive recovery actions.

## Symptoms

Typical symptoms can include:

- Rancher returning 502/503 or failing startup/readiness checks
- `kubectl` timing out or the local API endpoint refusing connections
- RKE2/containerd/kubelet repeatedly restarting or becoming unresponsive
- embedded etcd showing slow requests, readiness failures, or leader instability
- pods remaining Pending/Unknown longer than expected
- Longhorn volumes becoming degraded or detached
- Linux tasks entering uninterruptible `D` state
- high `%iowait`, high `await`, long block-device queues, or elevated Linux PSI I/O pressure
- kernel messages such as `Buffer I/O error`, `blk_update_request`, filesystem write errors, or iSCSI resets

## 1. Do not assume etcd corruption

If the API server is unavailable, do not immediately reset the cluster, remove etcd members, delete the etcd database, or restart all control-plane nodes.

First determine whether etcd is unhealthy because the underlying host storage is unhealthy.

```bash
systemctl status rke2-server --no-pager
journalctl -u rke2-server --since '-30 min' --no-pager | grep -Ei 'etcd|leader|quorum|slow|fsync|timeout|error'
```

When the node itself cannot complete filesystem I/O promptly, etcd can become a victim rather than the original cause.

## 2. Check host storage pressure

```bash
uptime
free -h
df -h
df -i
vmstat 1 10
cat /proc/pressure/io
iostat -xz 1 10
```

Pay particular attention to:

- `%iowait`
- `r_await` and `w_await`
- `aqu-sz`
- `%util`
- PSI `some` and `full`

One high sample does not prove a sustained incident. Compare several live samples and look for persistent latency or queue buildup.

The first block printed by `iostat` is generally an average since boot; the following interval samples are more useful for current-state diagnosis.

## 3. Inspect kernel and filesystem evidence

```bash
dmesg -T | grep -Ei 'I/O error|Buffer I/O|blk_update_request|EXT4-fs|XFS|reset|iscsi|blocked for more than'
journalctl -k --since '-60 min' | grep -Ei 'I/O|EXT4|XFS|reset|iscsi|blocked'
```

Kernel-level write errors are stronger evidence than application-level timeouts because they show the problem reaching the block/filesystem layer.

## 4. Map storage paths and failure domains

Determine whether RKE2, etcd, containerd, and Longhorn are competing for the same underlying disk.

```bash
lsblk -f
findmnt /
findmnt /var/lib/rancher/rke2
findmnt /var/lib/longhorn
```

A common small-cluster design is:

```text
root disk
├── OS
├── /var/lib/rancher/rke2
├── etcd
├── containerd
└── /var/lib/longhorn
```

This works, but it provides little I/O isolation. A storage storm can affect both application data and the control plane simultaneously.

## 5. Inspect RKE2 and Kubernetes state

Use the RKE2 kubeconfig explicitly when the shell does not already have one configured:

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get nodes -o wide
kubectl get pods -A -o wide | grep -Ev 'Running|Completed'
kubectl get --raw='/readyz?verbose'
```

If `kubectl` tries `http://localhost:8080`, that usually means no kubeconfig was loaded; it is not by itself proof that the cluster API is down.

For persistent shell configuration:

```bash
echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' > /etc/profile.d/rke2-kubeconfig.sh
chmod 644 /etc/profile.d/rke2-kubeconfig.sh
```

## 6. Check Longhorn health and capacity

```bash
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get nodes.longhorn.io -n longhorn-system -o json | jq -r '.items[] | .metadata.name as $n | .status.diskStatus | to_entries[] | .value as $d | [$n,$d.storageMaximum,$d.storageAvailable,$d.storageScheduled,(([$d.conditions[]? | select(.type=="Schedulable") | .status][0]) // "UNKNOWN")] | @tsv'
```

For a suspicious detached or degraded volume, map it back to Kubernetes before deleting anything:

```bash
VOL=<longhorn-volume-name>
kubectl get volumes.longhorn.io "$VOL" -n longhorn-system -o yaml
kubectl get pv,pvc -A -o wide | grep "$VOL" || true
kubectl get replicas.longhorn.io -n longhorn-system -o wide | grep "$VOL" || true
kubectl get engines.longhorn.io -n longhorn-system -o wide | grep "$VOL" || true
```

A detached volume is not automatically orphaned. It may belong to a scaled-to-zero workload.

## 7. Recover by reducing pressure first

Prefer relieving the storage bottleneck rather than repeatedly restarting the control plane.

Examples:

- scale down a nonessential, write-heavy workload
- remove confirmed unused PVCs only after mapping them to their owners
- free root-disk capacity without deleting Kubernetes or Longhorn data blindly
- temporarily cordon a node while storage recovers
- avoid restarting all etcd/control-plane nodes together

If a workload is contributing heavily to storage pressure, reduce it first and observe whether PSI and disk latency recover.

## 8. Validate recovery

A reachable Rancher UI is not enough.

```bash
kubectl get nodes
kubectl get pods -A | egrep 'CrashLoopBackOff|Error|Pending' || true
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get --raw='/readyz?verbose' | egrep 'etcd|readyz'
cat /proc/pressure/io
iostat -xz 1 3
```

Recovery should include:

- all expected nodes `Ready`
- etcd and `etcd-readiness` passing
- no sustained CrashLoop/Pending condition caused by the incident
- Longhorn volumes healthy or intentionally detached
- live disk latency back to normal operating ranges
- no new kernel I/O errors

## Root-cause wording

If the evidence proves that storage latency caused control-plane degradation but does not prove what caused the storage backend to slow down, document the result precisely:

> Confirmed failure mechanism: severe host/block-storage I/O latency caused RKE2, etcd, container runtime, filesystem, and Longhorn instability.
>
> Upstream trigger: not yet proven. Hypervisor/datastore saturation, backend storage faults, or workload-driven contention require separate infrastructure investigation.

Do not convert an unproven infrastructure trigger into a definitive root cause.

## Architecture improvements

For new production clusters, prefer separating control-plane storage from Longhorn data storage:

```text
OS/RKE2 disk
  OS
  etcd
  containerd
  kubelet

Dedicated Longhorn disk
  /data/longhorn
```

On virtual infrastructure, separate virtual disks only provide real fault isolation when the underlying datastores/failure domains are also independent.

## Principle

Inspect the machine state before changing cluster state. When storage is failing underneath Kubernetes, destructive etcd recovery steps can make a recoverable infrastructure incident much worse.