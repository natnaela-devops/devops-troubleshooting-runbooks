# DevOps Troubleshooting Runbooks

Practical troubleshooting and recovery runbooks built from real DevOps/SRE work across Linux, Kafka/KRaft, authentication, storage, and service operations.

> Sensitive infrastructure details, internal IPs, credentials, certificate material, and organization-specific identifiers are intentionally replaced with placeholders.

## Current runbooks

- [Kafka KRaft: Add SCRAM-SHA-512 authentication](runbooks/kafka/kraft-scram-authentication.md)
- [Kafka KRaft: Change listener and controller ports safely](runbooks/kafka/kraft-port-migration.md)
- [Kafka: Validate SCRAM authentication end to end](runbooks/kafka/scram-validation.md)
- [Kafka: mTLS client authentication with PKCS12](runbooks/kafka/mtls-client-authentication.md)
- [Spring Boot: Kafka SCRAM client configuration](runbooks/kafka/spring-boot-client-config.md)
- [Linux: Recover a full root filesystem caused by Docker logs](runbooks/linux/docker-json-log-disk-full.md)

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
- Never publish real secrets, private keys, keystores, certificates, or internal infrastructure identifiers.
- Prefer application-specific Kafka identities instead of sharing administrative credentials.

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
