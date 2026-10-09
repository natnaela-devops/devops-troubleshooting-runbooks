# Kubernetes Registry Secret and Image Pull Troubleshooting

This runbook covers workloads that cannot pull images because the image name, registry project, tag, or `imagePullSecrets` reference is wrong.

## Symptoms

```text
ImagePullBackOff
ErrImagePull
pull access denied
unauthorized: authentication required
manifest unknown
```

## 1. Inspect the pod event

```bash
kubectl -n <namespace> describe pod <pod>
```

Look at the exact image name and the Events section.

## 2. Confirm the deployment image

```bash
kubectl -n <namespace> get deploy <deployment> -o jsonpath='{.spec.template.spec.containers[*].image}{"\n"}'
```

Check registry host, project/repository, and tag separately.

## 3. Confirm the pull secret exists in the same namespace

```bash
kubectl -n <namespace> get secret
kubectl -n <namespace> get deploy <deployment> -o jsonpath='{.spec.template.spec.imagePullSecrets[*].name}{"\n"}'
```

A Secret in another namespace cannot satisfy the pod's `imagePullSecrets` reference.

## 4. Inspect secret type without exposing credentials

```bash
kubectl -n <namespace> get secret <registry-secret> -o jsonpath='{.type}{"\n"}'
```

Expected for a Docker registry credential:

```text
kubernetes.io/dockerconfigjson
```

## 5. Test the image independently

From a host that is allowed to reach the registry:

```bash
docker pull <registry>/<project>/<image>:<tag>
```

If a locally modified image was retagged, verify the new tag was actually pushed before changing the deployment.

## 6. Roll out the corrected image/secret

```bash
kubectl -n <namespace> set image deployment/<deployment> <container>=<registry>/<project>/<image>:<tag>
kubectl -n <namespace> rollout status deployment/<deployment>
```

If only the pull secret changed:

```bash
kubectl -n <namespace> rollout restart deployment/<deployment>
```

## Common mistakes

- secret name in the Deployment does not match the real Secret
- correct secret exists, but in the wrong namespace
- registry project/repository name changed
- tag was changed locally but never pushed
- workload still references the old image tag
- registry certificate trust is missing on the node/container runtime

Always read the pod event before recreating secrets blindly.
