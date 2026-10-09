# Docker Smoke Test for a Java Kafka mTLS Client Using JKS

This runbook covers validating a Spring Boot JAR in Docker before deploying it to Kubernetes/RKE2. The application expects JKS keystore/truststore files and environment-variable configuration.

## Expected environment variables

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

## Suggested layout

```text
transaction-analysis-test/
├── app.jar
├── env.list
└── certs/
    ├── kafka.keystore.jks
    └── kafka.truststore.jks
```

## Example `env.list`

```env
DATABASE_URL=jdbc:postgresql://<db-host>:5432/<db>
DATABASE_USER=<db-user>
DATABASE_PASSWORD=<secret>
KAFKA_URL=broker-1.example:18443,broker-2.example:18443,broker-3.example:18443
KAFKA_SECURITY_PROTOCOL=SSL
KAFKA_TRUSTSTORE_LOCATION=file:/etc/kafka-certs/kafka.truststore.jks
KAFKA_TRUSTSTORE_PASSWORD=<secret>
KAFKA_KEYSTORE_LOCATION=file:/etc/kafka-certs/kafka.keystore.jks
KAFKA_KEYSTORE_PASSWORD=<secret>
KAFKA_KEY_PASSWORD=<secret>
```

Do not commit `env.list` when it contains real credentials.

## Verify the JKS files first

```bash
keytool -list -v -keystore certs/kafka.keystore.jks | grep -E 'Alias|Owner|Issuer|Entry type'
keytool -list -v -keystore certs/kafka.truststore.jks | grep -E 'Alias|Owner|Issuer|Entry type'
```

Expected:

- client keystore contains a `PrivateKeyEntry`
- truststore contains the Kafka CA

## Run with Java 17

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

## Validation

Look for:

- successful Spring Boot startup
- PostgreSQL connectivity
- Kafka metadata/cluster connection
- `security.protocol=SSL`
- no `SSLHandshakeException`
- no missing-keystore/truststore errors

## Common failures

### `FileNotFoundException` for `/etc/kafka-certs/...`

The volume mount or filename does not match the application environment variables.

### Keystore/truststore password error

Verify interactively with `keytool` outside the container before debugging the application.

### Hostname verification failure

The broker certificate SAN must match the hostname/IP used in `KAFKA_URL`.

### App starts but Kafka never connects

Confirm the application actually maps the provided environment variables into Kafka client properties. Inspect runtime logs/config rather than assuming the variables are consumed.
