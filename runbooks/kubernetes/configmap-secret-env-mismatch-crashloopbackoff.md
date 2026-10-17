# Kubernetes CrashLoopBackOff from ConfigMap and Secret environment mismatches

This runbook documents a real deployment failure where newly deployed microservices entered `CrashLoopBackOff` because expected environment-variable keys were missing, misspelled, or referenced incorrectly from ConfigMaps and Secrets.

## Symptoms

- Pod repeatedly restarts after deployment.
- `kubectl logs` shows unresolved, empty, or invalid configuration values.
- `kubectl describe pod` shows missing Secret/ConfigMap references or restart activity.
- Application starts locally but fails only in Kubernetes.

## Root cause

The application expected specific environment-variable names, but the Kubernetes manifest loaded configuration dynamically with mismatched keys. In some cases, broad `envFrom` usage hid the mismatch because the deployment did not explicitly document which key populated which application property.

## Diagnostic workflow

```bash
kubectl get pod <pod> -n <namespace> -o wide
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous
kubectl get configmap <name> -n <namespace> -o yaml
kubectl get secret <name> -n <namespace> -o yaml
```

Compare the exact key names in Kubernetes with the names the application reads at runtime.

Where safe, inspect the effective environment without printing secret values:

```bash
kubectl exec -n <namespace> <pod> -- env | sed -E 's/(PASSWORD|PASS|SECRET|TOKEN|KEY)=.*/\1=[HIDDEN]/I'
```

## Remediation used

Configuration was made explicit with individual references rather than relying only on bulk `envFrom` imports.

```yaml
env:
  - name: DATABASE_HOST
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: DATABASE_HOST
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-secret
        key: DATABASE_PASSWORD
```

This makes missing keys visible in the deployment definition and reduces accidental naming drift.

Probe timing was also reviewed for Spring Boot services so cold startup was not mistaken for a dead application:

```yaml
readinessProbe:
  initialDelaySeconds: 15
livenessProbe:
  initialDelaySeconds: 15
```

Probe values must reflect the actual application startup profile; delays do not fix invalid configuration.

## Validation

After correcting references:

```bash
kubectl rollout restart deployment/<name> -n <namespace>
kubectl rollout status deployment/<name> -n <namespace>
kubectl get pods -n <namespace>
kubectl logs -f deployment/<name> -n <namespace>
```

Then verify the application can reach its real database, messaging, cache, or identity dependencies.

## Lesson

A Kubernetes pod that is `Running` or even `Ready` is not enough evidence that configuration is correct. Validate the effective runtime environment and application dependency path, not only the YAML source.