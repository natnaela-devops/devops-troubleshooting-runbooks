# RKE2 etcd member missing on one control-plane node

## Problem
One control-plane node in a three-node RKE2 cluster stopped participating normally while the other control-plane nodes remained functional.

## Symptoms
- Expected etcd listeners on TCP `2379` and `2380` were absent on the affected node.
- The etcd static-pod manifest existed.
- Temporary/bootstrap behavior appeared healthy, but the normal etcd static pod was not running.
- Cluster impact was isolated to one control-plane member.

## Investigation
```bash
sudo ss -lntp | grep -E ':2379|:2380'
sudo find /var/lib/rancher/rke2 -maxdepth 4 -type f | grep -Ei 'etcd|manifest'
sudo journalctl -u rke2-server -n 300 --no-pager
sudo df -hT
sudo df -ih
sudo stat /var/lib/rancher/rke2/server/db/etcd
```

If `crictl` is not in the normal PATH, locate the RKE2-bundled runtime tools or use `ctr` through the RKE2 containerd socket instead of assuming the command is globally installed.

## Diagnostic split
Check four possibilities independently:

1. etcd process/static pod crashes locally.
2. etcd membership no longer matches the node identity.
3. peer communication on `2380` is blocked.
4. local data/configuration differs from healthy members.

Compare the affected node with a healthy control-plane node before changing membership.

## Safety
Do not delete the etcd data directory or force-remove a member until quorum and current membership are known. In a three-member cluster, careless membership changes can turn a single-node incident into a control-plane outage.

## Verification
After recovery, verify:

```bash
sudo ss -lntp | grep -E ':2379|:2380'
sudo systemctl status rke2-server --no-pager
kubectl get nodes -o wide
kubectl get --raw='/readyz?verbose'
```

Then confirm etcd membership and endpoint health from a working control-plane context.

## Lesson
A present manifest is not proof that the static pod is actually running. Validate listeners, runtime state, logs, membership, disk state, and peer connectivity separately.