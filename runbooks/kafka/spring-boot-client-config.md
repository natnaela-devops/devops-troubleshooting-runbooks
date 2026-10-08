# Spring Boot Kafka Client with SCRAM-SHA-512

A Kafka username and password are not sufficient by themselves. The client must also know the security protocol and SASL mechanism.

## Recommended environment variables

```text
KAFKA_BOOTSTRAP_SERVERS=<BROKER_1>:18094,<BROKER_2>:18094,<BROKER_3>:18094
KAFKA_USERNAME=<SERVICE_USER>
KAFKA_PASSWORD=<SERVICE_PASSWORD>
```

The application can hardcode the stable protocol/mechanism values, or expose them as environment variables.

## Example `application.yaml`

```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS}
    properties:
      security.protocol: SASL_PLAINTEXT
      sasl.mechanism: SCRAM-SHA-512
      sasl.jaas.config: >
        org.apache.kafka.common.security.scram.ScramLoginModule required
        username="${KAFKA_USERNAME}"
        password="${KAFKA_PASSWORD}";
```

If the application exposes every setting externally, equivalent variables could be:

```text
KAFKA_SECURITY_PROTOCOL=SASL_PLAINTEXT
KAFKA_SASL_MECHANISM=SCRAM-SHA-512
```

The exact variable names are application-specific. What matters is that the resulting Kafka client configuration contains:

```properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
```

## Service accounts

Prefer a different SCRAM user for each microservice instead of distributing an administrative credential to every deployment.

Authentication identifies the user. Kafka ACLs are required when users must be restricted to particular topics, consumer groups, or operations.
