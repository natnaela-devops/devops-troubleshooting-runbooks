# Harbor push returns HTTP 500 when object storage endpoint is wrong

## Problem
Docker login and image build succeeded, but pushing an image to a Harbor registry failed with HTTP `500`.

## Investigation
Validate each Harbor component before blaming the registry as a whole:

```bash
kubectl get pods -A | grep -i harbor
kubectl get pvc -A | grep -i harbor
kubectl logs -n <namespace> <registry-pod> --tail=200
kubectl logs -n <namespace> <core-pod> --tail=200
```

Then verify the registry storage backend configuration and endpoint reachability from the registry pod.

For S3-compatible storage, confirm that the configured endpoint is the actual object-storage API endpoint, not a web/console endpoint.

```bash
kubectl exec -n <namespace> <registry-pod> -- env | grep -Ei 'storage|s3|bucket|endpoint'
kubectl exec -n <namespace> <registry-pod> -- sh -c 'getent hosts <storage-service>'
kubectl exec -n <namespace> <registry-pod> -- sh -c 'curl -vk http://<storage-service>:<api-port>/'
```

## Important diagnostic clue
An HTTP `200` from a storage console/UI port proves only that the UI is reachable. It does not prove that Harbor Registry can access the S3-compatible API it needs for blob storage.

Also distinguish host DNS from cluster DNS. A Kubernetes service name may resolve correctly inside the cluster while failing from the node shell.

## Verification
After correcting the storage endpoint/configuration, retry with a small test image:

```bash
docker pull hello-world
docker tag hello-world <registry>/<project>/storage-smoke:test
docker push <registry>/<project>/storage-smoke:test
```

Then inspect registry logs and verify that the artifact appears in Harbor.

## Lesson
When Harbor returns a server-side push error, separate authentication, registry process health, PVC health, DNS, and object-storage API reachability. A healthy Harbor UI does not prove that the registry backend can persist layers.