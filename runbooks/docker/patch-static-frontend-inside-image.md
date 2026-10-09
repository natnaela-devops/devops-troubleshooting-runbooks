# Patch a Static Frontend Inside an Existing Container Image

This runbook covers a controlled emergency change where a compiled frontend bundle inside an existing image contains an obsolete API URL and rebuilding from source is not immediately available.

> Prefer a proper source rebuild for normal releases. This procedure is for controlled recovery/testing and must result in a new image tag.

## 1. Create a disposable container

```bash
docker rm -f frontend-edit 2>/dev/null || true
docker create --name frontend-edit <registry>/<project>/<image>:<old-tag>
docker start frontend-edit
```

## 2. Locate the compiled asset

```bash
docker exec frontend-edit sh -c "grep -RIl '<old-url>' /usr/share/nginx/html 2>/dev/null"
```

Confirm the replacement target before editing.

## 3. Replace the value

```bash
docker exec frontend-edit sh -c "sed -i 's#<old-url>#<new-url>#g' /usr/share/nginx/html/assets/<bundle>.js"
```

## 4. Verify old and new values

```bash
docker exec frontend-edit sh -c "grep -R '<old-url>' /usr/share/nginx/html | wc -l"
docker exec frontend-edit sh -c "grep -R '<new-url>' /usr/share/nginx/html | wc -l"
```

The old value should be absent and the new value should appear where expected.

## 5. Commit to a new tag

```bash
docker commit frontend-edit <registry>/<project>/<image>:<new-tag>
docker push <registry>/<project>/<image>:<new-tag>
```

Never overwrite the original tag when using this emergency workflow.

## 6. Update the workload

```bash
kubectl -n <namespace> set image deployment/<deployment> <container>=<registry>/<project>/<image>:<new-tag>
kubectl -n <namespace> rollout status deployment/<deployment>
```

## Validation

- workload pulls the new tag
- frontend loads normally
- browser/API requests target the intended endpoint
- old URL is not present in the running image

Record the temporary patch and replace it later with a reproducible source-level build.
