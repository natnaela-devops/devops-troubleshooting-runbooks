# RKE2 + Longhorn Storage Design Guide

This guide explains when Longhorn is useful, why host-local storage behaves differently, and how to design storage for a fresh RKE2 cluster.

## Why Longhorn exists

Kubernetes can restart a pod on another node, but a pod that writes only to host-local storage does not automatically take its data with it.

Example:

```text
node-1: application + /data/app
node-2: no copy of /data/app
node-3: no copy of /data/app
```

If the pod moves from node-1 to node-2, host-local data remains on node-1.

Longhorn provides replicated block storage that can be attached to workloads through Kubernetes PVCs.

```text
PVC
 |
Longhorn volume
 |---- replica on node-1
 |---- replica on node-2
 `---- replica on node-3
```

If one node fails, Kubernetes can reschedule the workload and Longhorn can attach the logical volume using surviving replicas.

## When to use Longhorn

Longhorn is a good fit for:

- private or bare-metal Kubernetes clusters without an enterprise SAN CSI driver
- small to medium clusters that need replicated persistent volumes
- application databases that do not already provide their own storage replication
- Grafana, application state, uploads, internal services, and other RWO PVC workloads
- edge or branch environments built from commodity servers

## When host/local storage may be better

Host-local storage is useful for:

- caches and temporary data
- `emptyDir` workloads
- scratch files
- logs that are shipped elsewhere
- distributed systems that already replicate data at the application layer

Examples of systems that may deliberately use local fast disks include Kafka, YugabyteDB, Cassandra, OpenSearch/Elasticsearch, or Ceph. These systems already implement data replication, so combining application replication with three Longhorn replicas can create excessive write amplification and storage consumption.

The decision should be based on the application's failure model, not on using one storage class for everything.

## Installation order

Longhorn does **not** get installed before RKE2. Longhorn itself runs inside Kubernetes.

Correct sequence:

```text
1. Provision physical or virtual servers
2. Install Linux
3. Prepare and mount storage disks
4. Install Longhorn prerequisites
5. Install and form the RKE2 cluster
6. Verify Kubernetes and etcd health
7. Install Longhorn
8. Configure Longhorn disks/paths
9. Create a test PVC and validate failover
10. Deploy applications
```

## Recommended three-node layout

For a small three-node RKE2 cluster, prefer separate OS and Longhorn disks.

```text
node-1
  /dev/sda -> OS + RKE2 + etcd + containerd
  /dev/sdb -> /data/longhorn

node-2
  /dev/sda -> OS + RKE2 + etcd + containerd
  /dev/sdb -> /data/longhorn

node-3
  /dev/sda -> OS + RKE2 + etcd + containerd
  /dev/sdb -> /data/longhorn
```

This is safer than placing everything on one root disk:

```text
/
├── OS
├── etcd
├── containerd
├── kubelet
└── Longhorn replicas
```

When etcd, containerd, applications, and Longhorn all compete for one disk, a storage-latency incident can affect both the workload and the Kubernetes control plane.

## Preparing the Longhorn disk

Example only; adapt filesystem, device name, and mount options to the environment.

```bash
mkfs.ext4 /dev/sdb
mkdir -p /data/longhorn
mount /dev/sdb /data/longhorn
```

Persist the mount in `/etc/fstab` using the filesystem UUID rather than relying on `/dev/sdb` naming.

Verify:

```bash
lsblk -f
findmnt /data/longhorn
df -h /data/longhorn
```

Then configure Longhorn to use `/data/longhorn` on each intended storage node.

Longhorn should be given intentionally designed storage; it should not simply "take all storage" on the server.

## Prerequisites

On Ubuntu-family systems, typical prerequisites include iSCSI support and NFS client packages for Longhorn features that need them.

```bash
apt update
apt install -y open-iscsi nfs-common
systemctl enable --now iscsid
```

Run the Longhorn environment/preflight checks for the exact Longhorn release before installation.

## Installing Longhorn after RKE2

Example Helm flow:

```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace
```

After installation, verify all Longhorn nodes/disks are schedulable before creating production PVCs.

## Replication and usable capacity

A 100 GiB Longhorn volume with three replicas can consume approximately 300 GiB of raw storage.

```text
100 GiB logical volume
x 3 replicas
= ~300 GiB raw storage
```

Therefore, three nodes with 500 GiB available each do not provide 1.5 TiB of safely usable replicated capacity when the replica count is three.

Additional free space is required for:

- replica rebuilds
- snapshots
- filesystem overhead
- node maintenance
- temporary imbalance after failures

Running Longhorn storage close to full can leave no eligible node on which to rebuild a failed replica.

## Failure domains matter

Three Longhorn replicas do not guarantee protection against every infrastructure failure.

If three Kubernetes VMs use separate virtual disks but all those disks live on the same physical datastore, the actual topology is still:

```text
           shared datastore
             /    |    \
          node1 node2 node3
```

A datastore-wide latency event can affect all replicas together.

For stronger resilience, distribute storage replicas across genuinely independent failure domains where possible:

- separate physical hosts
- separate datastores
- separate storage controllers or pools
- separate racks/zones when supported

## Longhorn versus enterprise SAN/CSI

If the environment already has enterprise storage with a supported Kubernetes CSI driver, Longhorn may not be necessary.

Examples include enterprise SAN/NAS or cloud storage systems with their own CSI integration.

In that design, the external storage system provides durability while Kubernetes uses the vendor CSI driver for dynamic provisioning and attachment.

Longhorn is especially useful when the cluster needs to turn node-local disks into Kubernetes-managed replicated storage without relying on an external storage platform.

## Longhorn replication is not backup

Replication protects against certain storage/node failures; it does not protect against logical deletion.

If an administrator or application deletes data, Longhorn can faithfully replicate that deletion to every replica.

Use independent backups for recovery from:

- accidental deletion
- application corruption
- ransomware or credential compromise
- cluster-wide failures
- storage backend failures beyond the Longhorn failure domain

## Recommended design principle

Use the storage model that matches the workload:

```text
emptyDir / ephemeral
  -> temporary/cache/scratch data

local PV / local disk
  -> applications with their own replication or very high local-I/O requirements

Longhorn
  -> general replicated Kubernetes persistent storage

external CSI
  -> enterprise/cloud storage already available to the environment
```

The safest design is intentional: know where the bytes physically live, how many copies exist, which failures those copies survive, and how the data will be restored when replication is not enough.