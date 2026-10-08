# Kafka SCRAM Authentication Validation

Validate authentication before migrating applications.

## Correct credentials

Create a temporary client configuration:

```bash
cat > /tmp/kafka-sasl.properties <<'EOF_CLIENT'
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="<KAFKA_USERNAME>" password="<KAFKA_PASSWORD>";
EOF_CLIENT
chmod 600 /tmp/kafka-sasl.properties
```

List topics through the authenticated listener:

```bash
/opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server 127.0.0.1:18094 \
  --command-config /tmp/kafka-sasl.properties \
  --list
```

## Wrong-password test

```bash
cat > /tmp/kafka-sasl-wrong.properties <<'EOF_CLIENT'
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="<KAFKA_USERNAME>" password="WrongPassword";
EOF_CLIENT
chmod 600 /tmp/kafka-sasl-wrong.properties
```

Expected failure:

```text
SaslAuthenticationException: Authentication failed ... invalid credentials ... SCRAM-SHA-512
```

## Cross-node producer/consumer test

On node A:

```bash
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server 127.0.0.1:18094 \
  --consumer.config /tmp/kafka-sasl.properties \
  --topic test-topic \
  --from-beginning
```

On node B:

```bash
/opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server 127.0.0.1:18094 \
  --producer.config /tmp/kafka-sasl.properties \
  --topic test-topic
```

Send:

```text
kafka-auth-cross-node-test
```

The consumer should receive the same message. This proves authenticated traffic across multiple brokers rather than only a loopback test on one host.
