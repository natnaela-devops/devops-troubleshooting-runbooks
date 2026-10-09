# RKE2 Application Kafka mTLS with JKS

This runbook covers preparing an application-specific Kafka client identity for a Spring Boot workload running on RKE2 when the application expects Java JKS keystore and truststore files.

> Never create a second CA just because an application example shows one. If the Kafka brokers already use a trusted internal Kafka CA, sign the new application certificate with that CA so the broker can validate it.

## 1. Create a dedicated client identity

Example client identity:

```text
CN=transaction-analysis
```

Use one certificate identity per application. Do not reuse an unrelated application's client identity.

## 2. Create the JKS truststore

Import the Kafka CA certificate:

```bash
keytool -importcert -noprompt \
  -alias kafka-ca \
  -file ca.crt \
  -keystore kafka.truststore.jks \
  -storetype JKS
```

Enter the truststore password interactively.

## 3. Create the JKS client keystore

```bash
keytool -genkeypair \
  -alias transaction-analysis \
  -keyalg RSA \
  -keysize 2048 \
  -validity 825 \
  -dname 'CN=transaction-analysis,O=ExampleOrg' \
  -keystore kafka.keystore.jks \
  -storetype JKS
```

Create a CSR:

```bash
keytool -certreq \
  -alias transaction-analysis \
  -file transaction-analysis.csr \
  -keystore kafka.keystore.jks
```

Sign the CSR with the existing Kafka CA:

```bash
openssl x509 -req \
  -in transaction-analysis.csr \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -out transaction-analysis.crt \
  -days 825
```

Import the CA first, then the signed client certificate:

```bash
keytool -importcert -noprompt \
  -alias kafka-ca \
  -file ca.crt \
  -keystore kafka.keystore.jks

keytool -importcert -noprompt \
  -alias transaction-analysis \
  -file transaction-analysis.crt \
  -keystore kafka.keystore.jks
```

## 4. Verify both stores

```bash
keytool -list -v -keystore kafka.keystore.jks | grep -E 'Alias|Owner|Issuer|Valid|Entry type'
keytool -list -v -keystore kafka.truststore.jks | grep -E 'Alias|Owner|Issuer|Entry type'
```

Expected:

- client keystore contains a `PrivateKeyEntry`
- client certificate is issued by the Kafka CA
- truststore contains the Kafka CA as a trusted certificate

## 5. Expected application environment variables

A Spring Boot deployment may expose the Kafka and database configuration through variables such as:

```text
DATABASE_URL
DATABASE_USER
DATABASE_PASSWORD
KAFKA_URL
KAFKA_SECURITY_PROTOCOL
KAFKA_TRUSTSTORE_LOCATION
KAFKA_TRUSTSTORE_PASSWORD
KAFKA_KEYSTORE_LOCATION
KAFKA_KEYSTORE_PASSWORD
KAFKA_KEY_PASSWORD
```

Typical Kafka values:

```text
KAFKA_URL=broker-1.example:18443,broker-2.example:18443,broker-3.example:18443
KAFKA_SECURITY_PROTOCOL=SSL
KAFKA_TRUSTSTORE_LOCATION=file:/etc/kafka-certs/kafka.truststore.jks
KAFKA_KEYSTORE_LOCATION=file:/etc/kafka-certs/kafka.keystore.jks
```

Confirm the application actually maps these variables into Kafka client properties.

## 6. Optional Docker preflight before RKE2

Before creating Kubernetes Secrets, the same JAR can be tested with the JKS files mounted read-only:

```bash
docker run --rm \
  --name transaction-analysis-test \
  --env-file env.list \
  -v "$(pwd)/certs:/etc/kafka-certs:ro" \
  -v "$(pwd)/app.jar:/app/app.jar:ro" \
  -p 8989:8989 \
  eclipse-temurin:17-jre \
  java -jar /app/app.jar
```

Do not commit an `env.list` containing real credentials.

## 7. Create Kubernetes Secrets

```bash
kubectl create namespace taf

kubectl -n taf create secret generic kafka-certs \
  --from-file=kafka.keystore.jks \
  --from-file=kafka.truststore.jks
```

Application credentials and database credentials should be stored separately:

```bash
kubectl -n taf create secret generic transaction-analysis-env \
  --from-literal=KAFKA_KEYSTORE_PASSWORD='<secret>' \
  --from-literal=KAFKA_TRUSTSTORE_PASSWORD='<secret>' \
  --from-literal=KAFKA_KEY_PASSWORD='<secret>' \
  --from-literal=DATABASE_PASSWORD='<secret>'
```

## 8. Mount certs read-only and inject environment variables

Mount the Secret under `/etc/kafka-certs` with `readOnly: true` and inject non-secret values directly plus password values from the environment Secret.

## 9. Important hostname-verification note

If the application connects using broker IP addresses, those IPs must be present in the broker certificate SANs when endpoint verification is enabled.

If the application connects using a Kubernetes DNS name such as:

```text
kafka.kafka.svc
```

then the broker certificate must contain that DNS name in its SANs, or a network endpoint with a matching certificate must be used.

Do not disable endpoint verification merely to work around a SAN mismatch.

## 10. Verify deployment

```bash
kubectl -n taf rollout status deploy/transaction-analysis
kubectl -n taf logs deploy/transaction-analysis | grep -E 'Started|Kafka|SSL|ERROR'
kubectl -n taf exec deploy/transaction-analysis -- ls -l /etc/kafka-certs
```

## 11. Rotate the cert Secret

```bash
kubectl -n taf create secret generic kafka-certs \
  --from-file=kafka.keystore.jks \
  --from-file=kafka.truststore.jks \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n taf rollout restart deploy/transaction-analysis
```

## Common failures

### `Could not resolve placeholder 'KAFKA_KEYSTORE_PASSWORD'`

The environment Secret is missing or does not contain the expected key.

### `FileNotFoundException` for `/etc/kafka-certs/...`

The Secret mount is missing, path is wrong, or the key names differ from the filenames expected by the application.

### SSL handshake failure

Check CA trust, client certificate chain, keystore password, key password, and whether the Kafka URL points to the SSL listener.

### Connection reaches broker but hostname verification fails

Fix broker SANs or use the broker hostname/IP that the certificate actually covers.
