# Rancher/Kubernetes Binary Secret Double-Base64 Troubleshooting

This runbook covers a common failure when binary files such as PKCS12 or JKS keystores are added to a Kubernetes Secret through Rancher UI.

## Symptom

A Secret mounts successfully, but the application cannot read the keystore or truststore. Inside the pod, the mounted file is larger than the original and prints readable Base64 text such as:

```text
MII...
```

For JKS, a Base64-encoded file may begin with text similar to:

```text
/u3+7Q...
```

The Secret volume itself can look normal:

```text
client-keystore.p12 -> ..data/client-keystore.p12
truststore.p12      -> ..data/truststore.p12
```

The symlinks are expected Kubernetes Secret-volume behavior and are not the problem.

## Root cause

Kubernetes Secret `data:` values are Base64 encoded.

If a binary file is first converted to Base64 and that Base64 text is pasted into a Rancher form that treats the value as ordinary text, Rancher/Kubernetes may encode the text again.

The result is:

```text
binary file
  -> Base64 text
  -> Base64 encoded again
  -> Kubernetes decodes once
  -> pod receives Base64 text instead of the original binary
```

## Detect double encoding

Compare the mounted file size with the original:

```sh
wc -c /etc/kafka-certs/client-keystore.p12 /etc/kafka-certs/truststore.p12
```

Then inspect only a few bytes:

```sh
head -c 30 /etc/kafka-certs/client-keystore.p12
echo
```

A real PKCS12 or JKS file is binary. If the output is clean Base64-looking ASCII such as `MII...` or `/u3+7Q...`, the file is probably still encoded.

The strongest verification is SHA-256 comparison:

```sh
sha256sum /etc/kafka-certs/client-keystore.p12 /etc/kafka-certs/truststore.p12
```

Compare those hashes with the originals before the files were added to Kubernetes.

## Correct Rancher workflow

Generate exactly one Base64 layer from the original binary file:

```bash
base64 -w 0 client-keystore.p12 > client-keystore.p12.b64
base64 -w 0 truststore.p12 > truststore.p12.b64
```

Edit the Secret as YAML and place the Base64 strings directly under `data:`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-kafka-mtls
  namespace: application

type: Opaque
data:
  client-keystore.p12: <FIRST-LAYER-BASE64>
  truststore.p12: <FIRST-LAYER-BASE64>
```

Do not place already-Base64 values under `stringData:`. Do not pass them through a UI field that will encode the text again.

## Mount the Secret

```yaml
volumes:
  - name: kafka-mtls
    secret:
      secretName: app-kafka-mtls

containers:
  - name: application
    volumeMounts:
      - name: kafka-mtls
        mountPath: /etc/kafka-certs
        readOnly: true
```

The pod should receive:

```text
/etc/kafka-certs/client-keystore.p12
/etc/kafka-certs/truststore.p12
```

Kubernetes distributes the Secret to whichever worker runs the pod. The binary files do not need to be copied manually to every RKE2 node.

## Final verification

Inside the pod:

```sh
wc -c /etc/kafka-certs/client-keystore.p12 /etc/kafka-certs/truststore.p12
sha256sum /etc/kafka-certs/client-keystore.p12 /etc/kafka-certs/truststore.p12
```

The SHA-256 values must exactly match the original binary files.

For JKS, `keytool` can provide an additional identity check when it exists in the image:

```sh
keytool -list -v -keystore /etc/kafka-certs/kafka.keystore.jks \
  | grep -E 'Alias name:|Entry type:|Owner:|Issuer:'
```

`keytool` is not required at runtime; Java/Kafka can load the mounted keystore directly.

## Security notes

- Never commit keystores, truststores, private keys, passwords, Base64 Secret values, or real hashes from private infrastructure to a public repository.
- Keep password values in a separate Kubernetes Secret.
- Treat Base64 as encoding, not encryption.
