# Kafka KRaft: Add SCRAM-SHA-512 Authentication

This runbook adds a dedicated authenticated client listener to a three-node Kafka KRaft cluster while keeping existing broker/controller traffic separate.

## Target design

```text
Kafka node 1  <NODE_1_IP>
Kafka node 2  <NODE_2_IP>
Kafka node 3  <NODE_3_IP>

PLAINTEXT    18092   inter-broker / restricted administration
SASLCLIENT   18094   application clients using SCRAM-SHA-512
CONTROLLER   18275   KRaft controller quorum
```

## Broker configuration

Relevant `server.properties` values:

```properties
process.roles=broker,controller
node.id=<NODE_ID>

controller.quorum.voters=1@<NODE_1_IP>:18275,2@<NODE_2_IP>:18275,3@<NODE_3_IP>:18275

listeners=PLAINTEXT://0.0.0.0:18092,SASLCLIENT://0.0.0.0:18094,CONTROLLER://0.0.0.0:18275
advertised.listeners=PLAINTEXT://<THIS_NODE_IP>:18092,SASLCLIENT://<THIS_NODE_IP>:18094

controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SASLCLIENT:SASL_PLAINTEXT
inter.broker.listener.name=PLAINTEXT

sasl.enabled.mechanisms=SCRAM-SHA-512
listener.name.saslclient.sasl.enabled.mechanisms=SCRAM-SHA-512
listener.name.saslclient.scram-sha-512.sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required;
```

## Create a SCRAM user

Run against a currently reachable administrative listener:

```bash
/opt/kafka/bin/kafka-configs.sh \
  --bootstrap-server 127.0.0.1:18092 \
  --alter \
  --add-config 'SCRAM-SHA-512=[iterations=8192,password=<STRONG_PASSWORD>]' \
  --entity-type users \
  --entity-name <KAFKA_USERNAME>
```

Verify without displaying the password:

```bash
/opt/kafka/bin/kafka-configs.sh \
  --bootstrap-server 127.0.0.1:18092 \
  --describe \
  --entity-type users \
  --entity-name <KAFKA_USERNAME>
```

Expected:

```text
SCRAM credential configs for user-principal '<KAFKA_USERNAME>' are SCRAM-SHA-512=iterations=8192
```

## Client configuration

```properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="<KAFKA_USERNAME>" password="<KAFKA_PASSWORD>";
```

Store client files with restrictive permissions:

```bash
chmod 600 /path/to/client.properties
```

## Security notes

`SASL_PLAINTEXT` authenticates the client but does not encrypt network traffic. For networks where traffic confidentiality is required, use `SASL_SSL` and TLS certificates.

Do not distribute a Kafka administrative credential to every microservice. Create per-service SCRAM users and add ACL authorization where topic-level restrictions are required.
