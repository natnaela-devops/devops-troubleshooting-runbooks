# Kubernetes CrashLoopBackOff Caused by a Missing Log File or Directory

This runbook covers applications that start successfully enough to create a pod but then repeatedly crash because the process expects a local log path that does not exist or is not writable.

## 1. Confirm the CrashLoop

```bash
kubectl -n <namespace> get pods -o wide
kubectl -n <namespace> describe pod <pod-name>
```

Check current and previous logs:

```bash
kubectl -n <namespace> logs <pod-name>
kubectl -n <namespace> logs <pod-name> --previous
```

`--previous` is especially useful when the container exits quickly.

## 2. Look for file/path failures

Typical errors include:

```text
No such file or directory
Permission denied
/app/logs/application.log
```

Inspect the deployment:

```bash
kubectl -n <namespace> get deploy <deployment> -o yaml
```

Check:

- container image
- command and args
- `volumeMounts`
- `volumes`
- security context
- working directory

## 3. Inspect the image without changing the deployment

If the image is accessible locally:

```bash
docker run --rm --entrypoint sh <image> -c 'id; pwd; ls -ld /app /app/logs 2>/dev/null || true'
```

If the pod remains alive long enough:

```bash
kubectl -n <namespace> exec -it <pod-name> -- sh
```

## 4. Common fixes

### Application expects a directory that the image does not create

Fix the image:

```dockerfile
RUN mkdir -p /app/logs
```

and ensure the runtime user can write to it.

### Log directory should be ephemeral

Use an `emptyDir`:

```yaml
volumes:
  - name: app-logs
    emptyDir: {}

containers:
  - name: app
    volumeMounts:
      - name: app-logs
        mountPath: /app/logs
```

### Application should log to stdout instead

Prefer container-native stdout/stderr logging where the application supports it. Then collect logs with the cluster logging stack rather than requiring a local file.

## 5. Verify rollout

```bash
kubectl -n <namespace> rollout status deploy/<deployment>
kubectl -n <namespace> get pods -w
kubectl -n <namespace> logs deploy/<deployment> --tail=100
```

## Avoid these mistakes

- Do not keep restarting the pod without reading `--previous` logs.
- Do not create host directories manually on one Kubernetes node as a permanent fix.
- Do not assume `containerPort` creates a filesystem path or volume.
- Do not change unrelated ConfigMaps or Secrets until the actual crash reason is known.
