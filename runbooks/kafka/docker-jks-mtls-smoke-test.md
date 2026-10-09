# Docker Smoke Test for a Java Kafka mTLS Client Using JKS

This runbook covers validating a Spring Boot JAR in Docker before deploying it to Kubernetes/RKE2. The application expects Java 17, JKS keystore/truststore files, and environment-variable configuration.

The preferred test pattern is to build an application image first, then run that image with the JKS files mounted read-only. This more closely matches the final deployment model than launching a JAR directly from a generic Java base image.

## Application configuration model

A common Spring Boot pattern is to keep the packaged `application.yml` generic and inject all environment-specific values through environment variables, for example:

```yaml
spring:
  application:
    name: ${SPRING_APPLICATION_NAME}

  datasource:
    url: ${DATABASE_URL}
    username: ${DATABASE_USER}
    password: ${DATABASE_PASSWORD}
    driver-class-name: ${DATABASE_DRIVER}

  kafka:
    bootstrap-servers: ${KAFKA_URL}

    properties:
      security.protocol: ${KAFKA_SECURITY_PROTOCOL}
      ssl.endpoint.identification.algorithm: "${KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM}"

    ssl:
      trust-store-location: ${KAFKA_TRUSTSTORE_LOCATION}
      trust-store-password: ${KAFKA_TRUSTSTORE_PASSWORD}
      trust-store-type: ${KAFKA_TRUSTSTORE_TYPE}
      key-store-location: ${KAFKA_KEYSTORE_LOCATION}
      key-store-password: ${KAFKA_KEYSTORE_PASSWORD}
      key-store-type: ${KAFKA_KEYSTORE_TYPE}
      key-password: ${KAFKA_KEY_PASSWORD}

server:
  port: ${SERVER_PORT}
```

When the application already maps custom `KAFKA_*` variables directly, avoid adding a second parallel set of `SPRING_KAFKA_*` environment variables unless the application genuinely needs them. Duplicate configuration paths make it harder to determine which value won at runtime.

## Expected environment variables

Typical application-specific variables:

```text
SPRING_APPLICATION_NAME
DATABASE_URL
DATABASE_USER
DATABASE_PASSWORD
DATABASE_DRIVER
HIBERNATE_DIALECT
HIBERNATE_SHOW_SQL
KAFKA_URL
KAFKA_SECURITY_PROTOCOL
KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM
KAFKA_TRUSTSTORE_LOCATION
KAFKA_TRUSTSTORE_PASSWORD
KAFKA_TRUSTSTORE_TYPE
KAFKA_KEYSTORE_LOCATION
KAFKA_KEYSTORE_PASSWORD
KAFKA_KEYSTORE_TYPE
KAFKA_KEY_PASSWORD
KAFKA_PRODUCER_KEY_SERIALIZER
KAFKA_PRODUCER_VALUE_SERIALIZER
KAFKA_TRUSTED_PACKAGES
KAFKA_CONSUMER_GROUP_ID
KAFKA_CONSUMER_AUTO_OFFSET_RESET
KAFKA_CONSUMER_KEY_DESERIALIZER
KAFKA_CONSUMER_VALUE_DESERIALIZER
SERVER_PORT
KAFKA_TOPIC_NAME
```

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

EXPOSE 8080

ENTRYPOINT ["java","-jar","/app/app.jar"]
```

`EXPOSE` is documentation only; the actual reachable host port is controlled by Compose or `docker run` port mapping.

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
SPRING_APPLICATION_NAME=TransactionAnalysis

DATABASE_URL=jdbc:postgresql://<db-host>:5432/<db>
DATABASE_USER=<db-user>
DATABASE_PASSWORD=<secret>
DATABASE_DRIVER=org.postgresql.Driver

HIBERNATE_DIALECT=org.hibernate.dialect.PostgreSQLDialect
HIBERNATE_SHOW_SQL=true

KAFKA_URL=<broker-1>:18443,<broker-2>:18443,<broker-3>:18443
KAFKA_SECURITY_PROTOCOL=SSL
KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM=https

KAFKA_TRUSTSTORE_LOCATION=/etc/kafka-certs/kafka.truststore.jks
KAFKA_TRUSTSTORE_PASSWORD='<secret>'
KAFKA_TRUSTSTORE_TYPE=JKS

KAFKA_KEYSTORE_LOCATION=/etc/kafka-certs/kafka.keystore.jks
KAFKA_KEYSTORE_PASSWORD='<secret>'
KAFKA_KEYSTORE_TYPE=JKS
KAFKA_KEY_PASSWORD='<secret>'

KAFKA_PRODUCER_KEY_SERIALIZER=org.apache.kafka.common.serialization.StringSerializer
KAFKA_PRODUCER_VALUE_SERIALIZER=org.springframework.kafka.support.serializer.JsonSerializer
KAFKA_TRUSTED_PACKAGES=*

KAFKA_CONSUMER_GROUP_ID=<consumer-group>
KAFKA_CONSUMER_AUTO_OFFSET_RESET=latest
KAFKA_CONSUMER_KEY_DESERIALIZER=org.apache.kafka.common.serialization.StringDeserializer
KAFKA_CONSUMER_VALUE_DESERIALIZER=org.apache.kafka.common.serialization.StringDeserializer

SERVER_PORT=8080
KAFKA_TOPIC_NAME=<topic-name>
```

Kafka's `ssl.keystore.location` and `ssl.truststore.location` ultimately expect normal filesystem paths. If runtime logs show Kafka attempting to open a literal path such as `file:/etc/...`, switch the injected values to `/etc/...`.

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
      - "8989:8080"
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

## Validate the actual application port

Do not trust the Dockerfile `EXPOSE` value or an assumed source property. Verify the process inside the running container:

```bash
docker exec transaction-analysis-service sh -c 'ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null'
```

If Java is listening on container port `8080`, a host mapping such as `8989:8989` is wrong. Use:

```yaml
ports:
  - "8989:8080"
```

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
- intended Kafka bootstrap servers
- `security.protocol=SSL`
- `ssl.endpoint.identification.algorithm=https`
- JKS keystore/truststore paths
- Kafka cluster metadata
- consumer-group join
- partition assignment
- no `SSLHandshakeException`
- no missing-keystore/truststore errors

Useful validation filter:

```bash
docker logs transaction-analysis-service 2>&1 | grep -Ei 'Cluster ID|joined group|Successfully joined|assignment|assigned|SSLHandshakeException|authentication|disconnect|ERROR|WARN'
```

Strong evidence of a successful mTLS consumer connection includes:

```text
Cluster ID: <expected-cluster-id>
Successfully joined group
Finished assignment for group
Adding newly assigned partitions
partitions assigned
```

If the broker requires client certificates and the application reaches metadata, joins the group, and receives partition assignments over the mTLS listener, the client keystore/private-key identity and truststore are functioning correctly.

A container being `Up` is not sufficient proof. The strongest final validation is still a real business/test message being consumed or produced successfully.

## Common failures

### Kafka throws `NoSuchFileException: file:/etc/...`

The application passed a URI-style string into Kafka's filesystem-based SSL configuration. Inject a normal path instead:

```text
/etc/kafka-certs/kafka.keystore.jks
/etc/kafka-certs/kafka.truststore.jks
```

### `FileNotFoundException` for `/etc/kafka-certs/...`

The volume mount, filename, or configured path does not match.

Verify the files inside the container:

```bash
docker compose run --rm --entrypoint sh transaction-analysis-service -c 'ls -lah /etc/kafka-certs'
```

### Keystore/truststore password error

Verify the same files interactively with `keytool` outside the container before debugging the application.

### Hostname verification failure

The broker certificate SAN must match the hostname or IP used in the bootstrap server list. Keep endpoint identification set to `https`; do not disable hostname verification as a shortcut.

### App starts but Kafka never connects

Confirm the application actually maps the supplied environment variables into Kafka client properties. Inspect runtime producer/consumer configuration rather than assuming the intended variables are consumed.

### Host port is mapped to the wrong container port

Compare `docker ps` with the actual Java listener inside the container. Example:

```text
host 8989 -> container 8080
```

### Another service still uses the old Kafka listener

That is acceptable during a staged migration if the old listener intentionally remains available. Do not modify unrelated services until the new mTLS path has been validated independently.
