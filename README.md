# DevOps Troubleshooting Runbooks

Practical troubleshooting and recovery runbooks built from real DevOps/SRE work across Linux, Kafka/KRaft, authentication, storage, and service operations.

> Sensitive infrastructure details, internal IPs, credentials, and organization-specific identifiers are intentionally replaced with placeholders.

## Current runbooks

- [Kafka KRaft: Add SCRAM-SHA-512 authentication](runbooks/kafka/kraft-scram-authentication.md)
- [Kafka KRaft: Change listener and controller ports safely](runbooks/kafka/kraft-port-migration.md)
- [Kafka: Validate SCRAM authentication end to end](runbooks/kafka/scram-validation.md)
- [Linux: Recover a full root filesystem caused by Docker logs](runbooks/linux/docker-json-log-disk-full.md)
- [Spring Boot: Kafka SCRAM client configuration](runbooks/kafka/spring-boot-client-config.md)

## Principles used in these runbooks

- Inspect before changing.
- Back up configuration before edits.
- Separate broker/controller traffic from authenticated client traffic.
- Validate quorum health before and after Kafka changes.
- Test authentication with correct and intentionally incorrect credentials.
- Never publish real secrets in source control.
- Prefer application-specific Kafka users over sharing an administrative account.

## Example Kafka listener model

| Purpose | Example port | Security |
|---|---:|---|
| Inter-broker / temporary management | `18092` | PLAINTEXT, network-restricted |
| Application clients | `18094` | SASL_PLAINTEXT + SCRAM-SHA-512 |
| KRaft controller | `18275` | Controller traffic only |

For stronger transport security, use `SASL_SSL` with TLS rather than `SASL_PLAINTEXT`.
