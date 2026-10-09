# Kafka: Separate KRaft Quorum Health from Producer Failures

## Problem

An application reports Kafka publishing failures, and the first suspicion is that Kafka itself is down. In a KRaft cluster, the metadata quorum can be healthy while a producer still fails because of TLS, authentication, DNS, listener, topic, serialization, or application configuration problems.

## Check quorum health first

Run the appropriate Kafka metadata-quorum command for the installed version:

```bash
bin/kafka-metadata-quorum.sh --bootstrap-server <broker>:<port> describe --status
```

Confirm:

- a current leader exists;
- the expected voters are present;
- follower lag is small/stable;
- the leader epoch is progressing normally.

If the quorum is healthy, do not keep restarting brokers as the first response to an application producer error.

## Check broker/listener reachability

```bash
nc -vz <broker> <port>
openssl s_client -connect <broker>:<tls-port> -servername <broker-dns-name>
```

A successful TCP connection proves only reachability.

## Search application logs by failure stage

```bash
grep -Ei 'KafkaProducer|publishing|sent to kafka|SSLHandshakeException|SASL|authentication|timeout|ERROR' <application-log>
```

Classify the failure:

- connection refused / timeout -> routing, firewall, listener, DNS;
- `SSLHandshakeException` -> truststore, keystore, protocol, certificate, hostname;
- authentication error -> SASL/SCRAM or client-certificate identity;
- unknown topic/partition -> metadata/topic issue;
- serialization error -> application payload/configuration;
- publish log exists but downstream state is missing -> investigate acknowledgement and consumer path.

## Verify client configuration actually loaded

For Java/Spring applications, compare runtime environment values with the configuration supplied by the deployment. Check security protocol, bootstrap servers, truststore/keystore paths, passwords, and key password independently.

## Lesson

Kafka cluster health and Kafka client health are separate questions. Prove quorum state first, then troubleshoot the producer at the network, TLS/authentication, metadata, and application layers.