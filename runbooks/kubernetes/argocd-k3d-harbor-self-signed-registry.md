# Argo CD / k3d deployment failures with a self-signed Harbor registry

This runbook documents a real local GitOps failure where applications managed by Argo CD could not start because k3d/containerd did not trust the TLS certificate used by a self-hosted Harbor registry.

## Symptoms

- Argo CD reports the desired manifests as applied, but workloads cannot start.
- Pods enter `ImagePullBackOff` or `ErrImagePull`.
- Events contain an x509 error such as `certificate signed by unknown authority`.
- Images exist in Harbor and can be pushed from another trusted machine.

## Root cause

There are two separate trust/authentication layers:

1. **Registry TLS trust** — the k3d/containerd nodes must trust the CA that signed Harbor's certificate.
2. **Registry authentication** — Kubernetes must have valid Harbor credentials in the workload namespace and the Pod/ServiceAccount must reference them.

Adding only an `imagePullSecret` does not fix a CA trust failure.

## Fix the registry trust path

The Harbor root CA was mounted/configured for the k3d nodes and the registry was defined in the k3d registry configuration.

Conceptual `registries.yaml` pattern:

```yaml
mirrors:
  "harbor.local":
    endpoint:
      - "https://harbor.local"

configs:
  "harbor.local":
    tls:
      ca_file: /etc/ssl/certs/harbor-ca.crt
```

The actual CA path must exist inside the k3d node/containerd execution environment, not only on the host workstation.

## Create namespace-scoped registry credentials

```bash
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.local \
  --docker-username='<user>' \
  --docker-password='<password>' \
  --namespace=<application-namespace>
```

Do not commit real registry passwords into Git.

Reference the pull secret explicitly:

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
        - name: harbor-secret
```

For many workloads in one namespace, the secret can instead be associated with the intended ServiceAccount.

## Diagnose before changing Argo CD

```bash
kubectl describe pod <pod> -n <namespace>
kubectl get events -n <namespace> --sort-by=.lastTimestamp
kubectl get secret harbor-secret -n <namespace>
```

If the event is an x509 trust error, focus on node/containerd CA trust. If it is `unauthorized`, focus on credentials/project permissions. If it is `manifest unknown`, check repository/image/tag names.

## Validation

After trust and credentials are corrected:

1. force/retry the workload pull;
2. confirm the image is downloaded by the node runtime;
3. verify the Pod reaches `Running`/`Ready`;
4. confirm subsequent Argo CD syncs deploy new image tags without manual node changes.

## Lesson

Argo CD controls desired Kubernetes state; it is not the component that actually pulls application images. Registry failures must be traced through Argo CD -> Kubernetes Pod -> container runtime -> registry TLS/authentication.