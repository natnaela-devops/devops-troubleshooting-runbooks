# RKE2 ImagePullBackOff: Registry TCP resets and offline image import

## Incident pattern

A multi-container workload remains at `0/N` with `ImagePullBackOff`. Pulls of a large private-registry image fail intermittently while copying blobs:

```text
failed to pull and unpack image: failed to copy:
read tcp <node-ip>:<ephemeral-port>-><registry-ip>:443:
read: connection reset by peer
```

**Outcome:** The workload was restored and validated after obtaining the image from a separate workstation and importing an image archive into RKE2's containerd. This bypassed the failing transfer path; it did **not** establish or fix the underlying network/registry reset cause.

This runbook intentionally omits customer names, real hostnames/IPs, credentials, and registry image identifiers.

## 1. Differentiate authentication failures from transport failures

Check the image, pull policy, and effective pull-secret reference:

```bash
kubectl -n <namespace> get pods -o wide
kubectl -n <namespace> describe pod <pod>
kubectl -n <namespace> get deploy <deployment> \
  -o jsonpath='{.spec.template.spec.imagePullSecrets[*].name}{"\n"}'
kubectl -n <namespace> get secret <pull-secret> \
  -o jsonpath='{.type}{"\n"}'
```

For `kubernetes.io/dockerconfigjson`, list configured registry hostnames **without printing credentials**:

```bash
kubectl -n <namespace> get secret <pull-secret> \
  -o jsonpath='{.data.\.dockerconfigjson}' \
  | base64 -d | jq -r '.auths | keys[]'
```

A `401 Unauthorized` from an **unauthenticated** `GET /v2/` is normal for many private registries. A successful browser login or token endpoint response does not alone prove a repository pull will finish. A standalone `crictl pull` without credentials does not automatically use a Pod's imagePullSecret.

Validate DNS/TLS and reachability:

```bash
getent ahostsv4 <registry-host>
curl -v --connect-timeout 10 --max-time 30 https://<registry-host>/v2/
```

Keep TLS certificate verification enabled.

## 2. Diagnose repeated connection resets

On the affected node, inspect RKE2's containerd log:

```bash
sudo grep -Ei 'PullImage|failed to copy|connection reset|bytes read' \
  /var/lib/rancher/rke2/agent/containerd/containerd.log | tail -80
```

Multiple failed pulls with varying nonzero `bytes read` indicate that transfers are starting and then being interrupted; the counters are per attempt, **not** proof of fully downloaded image layers.

To capture TCP resets without writing application payloads:

```bash
sudo timeout 120 tcpdump -i any -nn \
  'host <registry-ip> and tcp port 443 and tcp[tcpflags] & tcp-rst != 0'
```

A packet appearing to originate from the registry IP and arriving at the node shows the **direction** of the RST. A firewall, proxy, or load balancer can inject resets; this capture does not conclusively attribute them to the registry application. Correlate exact timestamps and TCP source ports with Harbor, reverse-proxy, load-balancer, and firewall logs. Compare an actual image pull from a workstation on a **different network path**.

Do not restart RKE2 control-plane nodes, disable TLS, delete working pull secrets, or change timeouts blindly.

## 3. Recovery: pull elsewhere and export

On a trusted workstation with a reliable route to the registry and Docker installed:

```bash
docker login <registry-host>
docker pull --platform linux/amd64 <registry-host>/<project>/<image>:<tag>
docker image inspect <registry-host>/<project>/<image>:<tag> \
  --format '{{.Os}}/{{.Architecture}}'
docker save -o image.tar <registry-host>/<project>/<image>:<tag>
sha256sum image.tar
ls -lh image.tar
```

Use the cluster nodes' actual target platform rather than assuming `linux/amd64`. The archive SHA-256 is *different* from the registry manifest digest.

Transfer over SSH, using a jump host where necessary:

```bash
rsync -avP -e 'ssh -J <jump-user>@<jump-host>' \
  image.tar <node-user>@<node-ip>:/home/<node-user>/
```

`scp -o ProxyJump=...` or SFTP are also valid. `rsync -P` is useful if large transfers are interrupted.

## 4. Import into RKE2's runtime, not Docker's runtime

On the destination RKE2 node, verify checksum and free space:

```bash
sha256sum /home/<node-user>/image.tar
df -h /home/<node-user> /var/lib/rancher/rke2
```

Compare checksum with the workstation output. Import into the **`k8s.io`** namespace:

```bash
sudo /var/lib/rancher/rke2/bin/ctr \
  --address /run/k3s/containerd/containerd.sock \
  --namespace k8s.io \
  images import /home/<node-user>/image.tar
```

Verify through the Kubernetes CRI:

```bash
sudo /var/lib/rancher/rke2/bin/crictl \
  --runtime-endpoint unix:///run/k3s/containerd/containerd.sock \
  images | grep '<image>'
```

Docker may use `/run/containerd/containerd.sock`, while RKE2 uses `/run/k3s/containerd/containerd.sock`. Images in one store do **not** automatically appear in the other. Import onto **each node that may schedule the Pod**.

## 5. Reconcile image pull policy and validate

```bash
kubectl -n <namespace> get deploy <deployment> \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{" => "}{.imagePullPolicy}{"\n"}{end}'
kubectl -n <namespace> get pods -o wide
kubectl -n <namespace> rollout status deployment/<deployment>
```

- `IfNotPresent`: kubelet can use the imported local image when its name and tag match and the Pod is scheduled on the importing node.
- `Always`: kubelet still resolves the image from the registry; preloading may not bypass a broken connection.
- On GitOps-managed workloads, make any temporary pull-policy or scheduling change through the source of truth, not an untracked manual patch.

Confirm all expected containers are Ready, review events, and perform real service-level functional checks. Only then mark the recovery validated. Avoid deleting the archive until integrity and operational recovery are verified.

## Lessons learned

- A valid imagePullSecret and successful TLS handshake do not imply reliable blob transfer.
- A reset reproduced in both Docker and RKE2 suggests a shared external path, but does not identify the exact resetting device.
- Docker's `max-concurrent-downloads` may be **unsupported** with the containerd image store; heed daemon warnings rather than assuming the setting took effect.
- Never commit Docker credential files, decoded Kubernetes Secrets, customer-specific network addresses, registry tokens, or image archives.
- An offline import is a **service-restoration workaround**, not a permanent fix for the registry/network issue.
