# Longhorn PVCs stuck Terminating because of stale admission webhooks

## Problem
PersistentVolumeClaims backed by Longhorn remained in `Terminating` even after the workload namespace and PersistentVolumes were removed.

## Symptoms
- Namespace cleanup completed or was force-deleted.
- `kubectl get pv` showed no remaining PVs.
- Longhorn-backed PVCs stayed `Terminating`.
- Patch/delete operations failed because Kubernetes attempted to call a Longhorn validation webhook whose Service no longer existed.

Typical error pattern:

```text
failed calling webhook ... service "longhorn-admission-webhook" not found
```

## Investigation
```bash
kubectl get pvc -A
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep -i longhorn
kubectl get svc -A | grep -i longhorn
kubectl get endpoints -A | grep -i longhorn
kubectl get pvc <pvc> -n <namespace> -o yaml
```

Check finalizers, but do not immediately assume the finalizer itself is the only blocker. An unavailable admission webhook can prevent the API server from accepting the patch that would remove it.

## Recovery pattern
When Longhorn itself has already been intentionally removed and the webhook configuration is stale, remove only the orphaned webhook configuration after confirming that no active Longhorn installation still depends on it.

```bash
kubectl delete validatingwebhookconfiguration <stale-validator>
kubectl delete mutatingwebhookconfiguration <stale-mutator>
```

Retry the intended PVC cleanup only after the admission path is no longer broken.

## Verification
```bash
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep -i longhorn
kubectl get pvc -A
kubectl get ns
```

## Safety
Do not delete active Longhorn webhooks from a live storage installation. This procedure applies to orphaned admission configuration left behind during an intentional uninstall/cleanup.

## Lesson
A resource stuck in `Terminating` is not always a finalizer-only problem. A dead admission webhook can make even corrective API updates impossible.