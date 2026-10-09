# DevOps Troubleshooting Runbooks

Practical troubleshooting and recovery runbooks built from real DevOps/SRE work across Linux, Kafka/KRaft, Kubernetes/RKE2, Java, Redis, databases, authentication, storage, and service operations.

> Sensitive infrastructure details, internal IPs, credentials, certificate material, and organization-specific identifiers are intentionally replaced with placeholders.

## Kafka / KRaft

- [Kafka KRaft: Add SCRAM-SHA-512 authentication](runbooks/kafka/kraft-scram-authentication.md)
- [Kafka KRaft: Change listener and controller ports safely](runbooks/kafka/kraft-port-migration.md)
- [Kafka: Validate SCRAM authentication end to end](runbooks/kafka/scram-validation.md)
- [Kafka: mTLS client authentication with PKCS12](runbooks/kafka/mtls-client-authentication.md)
- [Kafka + WildFly: migrate an existing producer to mTLS](runbooks/kafka/wildfly-mtls-client-migration.md)
- [Kafka + RKE2: JKS mTLS client identity and Secrets](runbooks/kafka/rke2-jks-mtls-client.md)
- [Spring Boot: Kafka SCRAM client configuration](runbooks/kafka/spring-boot-client-config.md)

## Kubernetes / RKE2

- [CrashLoopBackOff caused by a missing log file or directory](runbooks/kubernetes/crashloopbackoff-missing-log-file.md)

## Java / Spring Boot

- [Java runtime version mismatch and unresolved Spring placeholders](runbooks/java/java-version-and-spring-placeholder-errors.md)

## Redis

- [Redis Cluster MOVED responses and proxy authentication](runbooks/redis/redis-cluster-moved-and-proxy-auth.md)

## Databases

- [Oracle object resolution and view inspection](runbooks/database/oracle-object-resolution-and-view-inspection.md)

## Linux

- [Recover a full root filesystem caused by Docker logs](runbooks/linux/docker-json-log-disk-full.md)

## Templates

- [Kafka SCRAM client properties](templates/kafka-client.properties.example)
- [Kafka mTLS client properties](templates/kafka-mtls-client.properties.example)

## Principles used in these runbooks

- Inspect before changing.
- Back up configuration before edits.
- Separate broker/controller traffic from application client traffic.
- Validate quorum health before and after Kafka changes.
- Use rolling broker restarts when the change allows it.
- Test authentication with both positive and intentional negative cases.
- Keep TLS hostname verification enabled and fix certificate SANs rather than disabling validation.
- Never publish real secrets, private keys, keystores, certificates, internal IPs, cluster identifiers, or environment-specific checksums.
- Prefer application-specific Kafka identities instead of sharing administrative credentials.
- Validate the runtime configuration actually loaded by the application, not only the source configuration you intended to deploy.

## Example Kafka listener model

| Purpose | Example port | Security |
|---|---:|---|
| Inter-broker / temporary management | `18092` | PLAINTEXT, network-restricted |
| Existing authenticated migration listener | `18094` | SASL_PLAINTEXT + SCRAM-SHA-512 |
| Application mTLS listener | `18443` | SSL + required client certificate |
| KRaft controller | `18275` | Controller traffic only |

The repository covers both common client authentication patterns:

- `SASL_SSL + SCRAM-SHA-512` when username/password authentication is required over encrypted transport.
- `SSL + mTLS` when applications authenticate with client certificates.

Choose the model required by the application and security architecture rather than mixing the two unintentionally.

## Expansion plan

This repository is intentionally growing into a sanitized record of real troubleshooting patterns encountered in day-to-day DevOps/SRE work. Additional runbooks will be added for RKE2 networking, VPN/DNS troubleshooting, observability, database connectivity, container image debugging, service startup failures, and production migration procedures as those cases are validated and generalized safely.
