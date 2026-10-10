# RKE2 Kafka mTLS Client with PKCS12

This runbook covers using application-specific PKCS12 client identities for Java/Spring workloads running on RKE2.

## Design

Use one client identity per logical application:

```text
app-a -> CN=app-a
app-b -> CN=app-b
app-c -> CN=app-c
```

Replicas of the same application may share one client identity. Different applications should not reuse the same client keystore.

A truststore can be shared when all applications trust the same Kafka CA, but separate per-application copies are also operationally simple.

## Generate a client certificate

Create a private key and CSR:

```bash
openssl genrsa -out app.key 2048
openssl req -new \
  -key app.key \
  -out app.csr \
  -subj '/C=XX/O=Example/OU=Kafka Clients/CN=app'
```

Use an extension file that includes client authentication:

```text
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
```

Sign the CSR with the existing Kafka CA:

```bash
openssl x509 -req \
  -in app.csr \
  -CA kafka-ca.crt \
  -CAkey kafka-ca.key \
  -CAcreateserial \
  -out app.crt \
  -days 825 \
  -sha256 \
  -extfile ext.cnf
```

Verify:

```bash
openssl verify -CAfile kafka-ca.crt app.crt
openssl x509 -in app.crt -noout -subject -issuer -dates -ext extendedKeyUsage
```

Expected extended key usage:

```text
TLS Web Client Authentication
```

## Build the PKCS12 keystore

Read the password interactively instead of writing it into shell history:

```bash
read -rsp 'PKCS12 password: ' STOREPASS; echo
export STOREPASS
```

Create the client keystore:

```bash
openssl pkcs12 -export \
  -inkey app.key \
  -in app.crt \
  -certfile kafka-ca.crt \
  -name app \
  -out client-keystore.p12 \
  -passout env:STOREPASS
```

Create the truststore containing only the Kafka CA:

```bash
keytool -importcert \
  -alias kafka-ca \
  -file kafka-ca.crt \
  -keystore truststore.p12 \
  -storetype PKCS12 \
  -storepass "$STOREPASS" \
  -noprompt
```

Verify both stores:

```bash
keytool -list -v -keystore client-keystore.p12 -storetype PKCS12
keytool -list -v -keystore truststore.p12 -storetype PKCS12
```

Expected:

- client keystore contains a `PrivateKeyEntry`
- client certificate subject matches the application identity
- truststore contains the Kafka CA as a `trustedCertEntry`

Clear the shell variable:

```bash
unset STOREPASS
```

## Kubernetes Secret

Create one binary Secret per application. With `kubectl`:

```bash
kubectl -n application create secret generic app-kafka-mtls \
  --from-file=client-keystore.p12 \
  --from-file=truststore.p12
```

For Rancher UI, use the first-layer Base64 values directly under YAML `data:`. See [Rancher/Kubernetes Binary Secret Double-Base64 Troubleshooting](../kubernetes/rancher-binary-secret-double-base64.md).

## Mount in the deployment

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

Runtime files:

```text
/etc/kafka-certs/client-keystore.p12
/etc/kafka-certs/truststore.p12
```

## Application configuration

A typical application-specific configuration is:

```text
APP_KAFKA_BOOTSTRAP_SERVERS=broker-1.example:18443,broker-2.example:18443,broker-3.example:18443
APP_KAFKA_SECURITY_PROTOCOL=SSL
APP_KAFKA_KEYSTORE_LOCATION=file:/etc/kafka-certs/client-keystore.p12
APP_KAFKA_TRUSTSTORE_LOCATION=file:/etc/kafka-certs/truststore.p12
APP_KAFKA_KEYSTORE_TYPE=PKCS12
APP_KAFKA_TRUSTSTORE_TYPE=PKCS12
APP_KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=https
```

Keep the keystore, truststore, and key passwords in a separate Secret.

Do not assume every Spring Boot application treats resource paths identically. Some configurations expect `file:/path`, while direct Kafka client properties may require a plain absolute filesystem path. Preserve the syntax proven by the application's own configuration and runtime behavior.

## Verify the mounted binaries

Inside the pod:

```sh
wc -c /etc/kafka-certs/client-keystore.p12 /etc/kafka-certs/truststore.p12
sha256sum /etc/kafka-certs/client-keystore.p12 /etc/kafka-certs/truststore.p12
```

Compare the hashes with the source files used to create the Secret. Exact matches prove that the binary Secret survived transfer and mounting without corruption or double encoding.

## Verify end-to-end behavior

A successful mTLS deployment is not proven by a mounted file alone. Validate the application path:

1. application starts without keystore/truststore load errors
2. Kafka producer or consumer connects to the intended SSL listener
3. no TLS handshake or hostname-verification errors appear
4. the expected business message is produced or consumed
5. downstream application behavior confirms successful processing

## Security notes

- Keep the CA private key only on the designated PKI/signing host.
- Do not copy unrelated applications' client keystores to make connectivity work.
- Base64 is not encryption.
- Never publish private keys, PKCS12/JKS files, passwords, internal addresses, or organization-specific certificate material.
