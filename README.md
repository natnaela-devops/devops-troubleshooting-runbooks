# DevOps Troubleshooting Runbooks

Practical troubleshooting and recovery runbooks built from real DevOps/SRE work across Linux, Kafka/KRaft, Kubernetes/RKE2, Java, Redis, databases, authentication, storage, observability, networking, automation, and service operations.

> Sensitive infrastructure details, internal IPs, credentials, certificate material, and organization-specific identifiers are intentionally replaced with placeholders.

See the [Troubleshooting Inventory](TROUBLESHOOTING-INVENTORY.md) for the broader list of confirmed, documented, and still-in-progress cases.

## Kafka / KRaft

- [Kafka KRaft: Add SCRAM-SHA-512 authentication](runbooks/kafka/kraft-scram-authentication.md)
- [Kafka KRaft: Change listener and controller ports safely](runbooks/kafka/kraft-port-migration.md)
- [Kafka: Validate SCRAM authentication end to end](runbooks/kafka/scram-validation.md)
- [Kafka: mTLS client authentication with PKCS12](runbooks/kafka/mtls-client-authentication.md)
- [Kafka + WildFly: migrate an existing producer to mTLS](runbooks/kafka/wildfly-mtls-client-migration.md)
- [Kafka + RKE2: JKS mTLS client identity and Secrets](runbooks/kafka/rke2-jks-mtls-client.md)
- [Kafka + Docker: smoke-test a Java JKS mTLS client](runbooks/kafka/docker-jks-mtls-smoke-test.md)
- [Spring Boot: Kafka SCRAM client configuration](runbooks/kafka/spring-boot-client-config.md)
- [Kafka: separate KRaft quorum health from producer failures](runbooks/kafka/quorum-vs-producer-failure-triage.md)

## Kubernetes / RKE2

- [CrashLoopBackOff caused by a missing log file or directory](runbooks/kubernetes/crashloopbackoff-missing-log-file.md)
- [RKE2 control-plane degradation from resource or disk I/O pressure](runbooks/kubernetes/rke2-control-plane-resource-io-degradation.md)
- [RKE2 etcd member missing on one control-plane node](runbooks/kubernetes/rke2-etcd-member-missing-on-one-node.md)
- [Registry secret, image tag, and ImagePullBackOff troubleshooting](runbooks/kubernetes/registry-secret-and-imagepull-troubleshooting.md)
- [Redis Cluster MOVED errors behind Kubernetes Services](runbooks/kubernetes/redis-cluster-moved-service-exposure.md)
- [Audit stale dependency endpoints across namespaces](runbooks/kubernetes/cross-namespace-config-audit.md)
- [Longhorn PVCs stuck Terminating because of stale admission webhooks](runbooks/kubernetes/longhorn-stale-webhook-pvc-terminating.md)

## Observability

- [OpenSearch: separate application and platform logs](runbooks/observability/opensearch-separate-application-platform-logs.md)
- [OpenSearch: validate the real event timestamp field](runbooks/observability/opensearch-timestamp-field-validation.md)
- [Prometheus + Alertmanager: validate Telegram alerts safely](runbooks/observability/prometheus-alertmanager-telegram-validation.md)
- [Prometheus: align retention with the required history window](runbooks/observability/prometheus-retention-history-window.md)

## Java / Spring Boot

- [Java runtime version mismatch and unresolved Spring placeholders](runbooks/java/java-version-and-spring-placeholder-errors.md)
- [Run a Java JAR with an environment file and nohup](runbooks/java/run-jar-with-env-file-and-nohup.md)
- [Trace a Java payment rollback to a missing required request field](runbooks/java/payment-rollback-missing-required-field.md)

## Identity / Keycloak

- [Keycloak startup failure caused by installation-directory ownership](runbooks/keycloak/keycloak-data-directory-permission-startup.md)

## Redis

- [Redis Cluster MOVED responses and proxy authentication](runbooks/redis/redis-cluster-moved-and-proxy-auth.md)
- [Validate Predixy authentication in an isolated Redis Cluster lab](runbooks/redis/predixy-authentication-validation-lab.md)

## Databases

- [Oracle object resolution and view inspection](runbooks/database/oracle-object-resolution-and-view-inspection.md)
- [Oracle phone-number normalization for lookup troubleshooting](runbooks/database/oracle-phone-number-normalization.md)
- [YugabyteDB YSQL Not Ready troubleshooting](runbooks/database/yugabytedb-ysql-not-ready.md)
- [Verify Flyway migration history before debugging the application](runbooks/database/flyway-migration-history-verification.md)
- [MySQL socket failure with Permission denied during startup](runbooks/database/mysql-socket-permission-denied-startup.md)

## Docker / Containers

- [Patch a static frontend inside an existing container image](runbooks/docker/patch-static-frontend-inside-image.md)
- [Harbor push HTTP 500 when object-storage endpoint is wrong](runbooks/docker/harbor-push-http500-object-storage-endpoint.md)

## Networking / VPN

- [FortiVPN certificate, routing, and DNS troubleshooting](runbooks/networking/fortivpn-certificate-and-dns-troubleshooting.md)
- [Repeated SMPP bind timeout: network reachability vs application retry](runbooks/networking/smpp-bind-timeout-network-triage.md)

## Linux

- [Recover a full root filesystem caused by Docker logs](runbooks/linux/docker-json-log-disk-full.md)
- [Fix duplicate SSH host keys after cloning Linux VMs](runbooks/linux/cloned-vm-duplicate-ssh-host-keys.md)
- [Discover nonstandard systemd services and runtime configuration](runbooks/linux/nonstandard-systemd-service-discovery.md)
- [Repair UEFI boot entries and GRUB without breaking Windows](runbooks/linux/uefi-grub-dual-boot-repair.md)
- [Diagnose Linux boot slowness with systemd-analyze](runbooks/linux/systemd-analyze-boot-slowness.md)

## Automation / Ansible

- [Ansible YAML ScannerError caused by malformed inline comments](runbooks/automation/ansible-yaml-scanner-error.md)
- [Legacy NodeSource repository causes npm/Node.js installation failures](runbooks/automation/legacy-nodesource-repository.md)

## Templates

- [Kafka SCRAM client properties](templates/kafka-client.properties.example)
- [Kafka mTLS client properties](templates/kafka-mtls-client.properties.example)

## Principles used in these runbooks

- Inspect before changing.
- Back up configuration before edits.
- Separate infrastructure health from application-level failure.
- Validate quorum health before and after Kafka or etcd changes.
- Use rolling restarts when the change allows it.
- Test authentication with both positive and intentional negative cases.
- Keep TLS hostname verification enabled and fix certificate SANs rather than disabling validation.
- Never publish real secrets, private keys, keystores, certificates, internal IPs, cluster identifiers, or environment-specific checksums.
- Validate the runtime configuration actually loaded by the application, not only the source configuration you intended to deploy.
- Distinguish transport reachability from application-level success; a reachable port is not proof that authentication or message delivery works.
- Do not label an incident resolved until the fix has been verified at the application or service level.
- If the original evidence did not prove the final root cause, document the investigation honestly instead of inventing a resolution.

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

This repository is a sanitized record of real troubleshooting patterns encountered in day-to-day DevOps/SRE work. Additional cases are generalized only when enough evidence exists to document the diagnosis and recovery accurately without exposing private infrastructure details.
