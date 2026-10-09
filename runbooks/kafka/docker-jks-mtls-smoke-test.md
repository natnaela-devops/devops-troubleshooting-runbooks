# Docker Smoke Test for a Java Kafka mTLS Client Using JKS

This runbook covers validating a Spring Boot JAR in Docker before deploying it to Kubernetes/RKE2. The application expects Java 17, JKS keystore/truststore files, and environment-variable configuration.

The preferred test pattern is to build an application image first, then run that image with the JKS files mounted read-only. This more closely matches the final deployment model than launching a JAR directly from a generic Java base image.

## Expected environment variables

Typical application-specific variables:

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

Some Spring Boot applications also consume the equivalent `SPRING_KAFKA_*` properties directly. If both configuration paths exist in the application, keep them aligned during migration testing so the application cannot silently fall back to an old bootstrap server or security protocol.

## Suggested layout

```text
transaction-analysis/
├── Dockerfile
├── docker-compose.yml
├── .env
└── transaction-analysis.jar
```

Keep the JKS delivery bundle outside the build context when possible:

```text
/root/kafka-client-jks/
├── kafka.keystore.jks
├── kafka.truststore.jks
└── SHA256SUMS
```

Do not COPY private keystores into the application image.

## Verify delivery integrity

Before using the JKS files:

```bash
cd /root/kafka-client-jks
sha256sum -c SHA256SUMS
```

Expected:

```text
kafka.keystore.jks: OK
kafka.truststore.jks: OK
```

Then inspect the stores:

```bash
keytool -list -keystore kafka.keystore.jks -storetype JKS
keytool -list -keystore kafka.truststore.jks -storetype JKS
```

Expected:

- client keystore contains the application identity as a `PrivateKeyEntry`
- truststore contains the Kafka CA as a `trustedCertEntry`

## Verify network reachability first

A successful TCP connection does not prove TLS authentication, but it quickly separates routing/firewall issues from Kafka client configuration problems.

```bash
for host in <broker-1> <broker-2> <broker-3>; do
  echo "=== $host ==="
  timeout 3 bash -c "</dev/tcp/$host/18443" && echo OK || echo FAILED
done
```

## Dockerfile

Use a Java 17 runtime image and package only the JAR:

```dockerfile
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

COPY transaction-analysis.jar /app/app.jar

EXPOSE 8989

ENTRYPOINT ["java","-jar","/app/app.jar"]
```

Build the reusable application image:

```bash
docker build -t transaction-analysis:mtls .
```

## Offline Docker host

If the target host has no internet access, prepare the Java base image on an internet-connected machine:

```bash
docker pull eclipse-temurin:17-jre-alpine
docker save -o eclipse-temurin-17-jre-alpine.tar eclipse-temurin:17-jre-alpine
sha256sum eclipse-temurin-17-jre-alpine.tar
```

Copy the tar file to the offline Docker host, verify its checksum there, then load it:

```bash
docker load -i eclipse-temurin-17-jre-alpine.tar
docker images | grep eclipse-temurin
```

The subsequent `docker build` can then use the locally loaded base image without internet access.

## Single `.env` file

For a simple Compose-based test, one `.env` file can be used both for Compose variable substitution and as the application environment file.

Example:

```env
HOST_IP=<docker-host-ip>

DATABASE_URL=jdbc:postgresql://<db-host>:5432/<db>
DATABASE_USER=<db-user>
DATABASE_PASSWORD=<secret>

KAFKA_URL=<broker-1>:18443,<broker-2>:18443,<broker-3>:18443
KAFKA_SECURITY_PROTOCOL=SSL
KAFKA_TRUSTSTORE_LOCATION=file:/etc/kafka-certs/kafka.truststore.jks
KAFKA_TRUSTSTORE_PASSWORD='<secret>'
KAFKA_KEYSTORE_LOCATION=file:/etc/kafka-certs/kafka.keystore.jks
KAFKA_KEYSTORE_PASSWORD='<secret>'
KAFKA_KEY_PASSWORD='<secret>'

SPRING_KAFKA_BOOTSTRAP_SERVERS=<broker-1>:18443,<broker-2>:18443,<broker-3>:18443
SPRING_KAFKA_PROPERTIES_SECURITY_PROTOCOL=SSL
SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_LOCATION=file:/etc/kafka-certs/kafka.truststore.jks
SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_PASSWORD='<secret>'
SPRING_KAFKA_PROPERTIES_SSL_TRUSTSTORE_TYPE=JKS
SPRING_KAFKA_PROPERTIES_SSL_KEYSTORE_LOCATION=file:/etc/kafka-certs/kafka.keystore.jks
SPRING_KAFKA_PROPERTIES_SSL_KEYSTORE_PASSWORD='<secret>'
SPRING_KAFKA_PROPERTIES_SSL_KEYSTORE_TYPE=JKS
SPRING_KAFKA_PROPERTIES_SSL_KEY_PASSWORD='<secret>'
```

If a secret contains characters such as `#`, `$`, `!`, or spaces, quote it so Compose does not parse part of the value as syntax.

Protect the file:

```bash
chmod 600 .env
```

Never commit a real `.env` file containing credentials.

## Compose pattern

Only migrate the target service first. Leave unrelated services on their existing Kafka path until the mTLS client is validated.

```yaml
services:
  transaction-analysis-service:
    restart: unless-stopped
    image: transaction-analysis:mtls
    container_name: transaction-analysis-service
    networks:
      - appnet
    ports:
      - "8989:8989"
    env_file:
      - ./.env
    volumes:
      - /root/kafka-client-jks:/etc/kafka-certs:ro

  existing-service:
    restart: unless-stopped
    image: existing-service:latest
    networks:
      - appnet
    environment:
      - SPRING_KAFKA_BOOTSTRAP_SERVERS=kafka:<existing-port>

networks:
  appnet:
    external: true
    driver: bridge
```

This isolates the migration: the new application can use the mTLS listener while another application continues using its existing listener.

## Validate Compose before starting

```bash
docker compose config
```

Review the rendered configuration carefully. Do not paste rendered output into tickets or public repositories if it contains resolved credentials.

Start only the target service during the first validation:

```bash
docker compose up -d transaction-analysis-service
```

## Runtime validation

Inspect logs:

```bash
docker logs -f transaction-analysis-service
```

Look for:

- successful Spring Boot startup
- PostgreSQL connectivity
- Kafka metadata/cluster connection
- the intended broker list
- `security.protocol=SSL`
- JKS keystore/truststore paths
- no `SSLHandshakeException`
- no missing-keystore/truststore errors

A container being `Up` is not sufficient proof. The application must actually establish the Kafka connection and, where possible, successfully consume or produce a test message.

## Common failures

### `FileNotFoundException` for `/etc/kafka-certs/...`

The volume mount, filename, or configured path does not match.

### Keystore/truststore password error

Verify the same files interactively with `keytool` outside the container before debugging the application.

### Hostname verification failure

The broker certificate SAN must match the hostname or IP used in the bootstrap server list. Do not disable endpoint verification as a shortcut.

### App starts but Kafka never connects

Confirm the application actually maps the supplied environment variables into Kafka client properties. Inspect runtime producer/consumer configuration rather than assuming the intended variables are consumed.

### Another service still uses the old Kafka listener

That is acceptable during a staged migration if the old listener intentionally remains available. Do not modify unrelated services until the new mTLS path has been validated independently.
