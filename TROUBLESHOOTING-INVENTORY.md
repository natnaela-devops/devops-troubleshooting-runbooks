# Troubleshooting Inventory

This file tracks troubleshooting patterns that were actually encountered or investigated. It intentionally separates documented/resolved patterns from cases that are still being validated.

Sensitive organization names, internal addresses, credentials, certificate material, and environment-specific identifiers are excluded.

## Kubernetes / RKE2

| Case | State | Runbook |
|---|---|---|
| CrashLoopBackOff caused by missing application log path/file | Documented | `runbooks/kubernetes/crashloopbackoff-missing-log-file.md` |
| RKE2 control-plane degradation under CPU/memory/disk-I/O pressure | Documented | `runbooks/kubernetes/rke2-control-plane-resource-io-degradation.md` |
| One RKE2 control-plane node missing etcd listeners/static-pod runtime | Documented | `runbooks/kubernetes/rke2-etcd-member-missing-on-one-node.md` |
| Registry secret, image tag, or ImagePullBackOff failures | Documented | `runbooks/kubernetes/registry-secret-and-imagepull-troubleshooting.md` |
| Redis Cluster `MOVED` redirects not reachable through Service design | Documented | `runbooks/kubernetes/redis-cluster-moved-service-exposure.md` |
| Stale dependency endpoints across ConfigMaps/namespaces | Documented | `runbooks/kubernetes/cross-namespace-config-audit.md` |
| Longhorn PVCs stuck Terminating because stale webhooks referenced a missing admission service | Documented | `runbooks/kubernetes/longhorn-stale-webhook-pvc-terminating.md` |
| RKE2/containerd runtime inspection using the RKE2 containerd socket | Confirmed operational pattern | Covered by related RKE2/container runbooks |
| Low-memory three-node cluster with multiple stateful/platform workloads | Confirmed | Covered by resource/I/O runbook |
| Longhorn/RKE2 filesystem pressure, especially `/var/lib/rancher` | Confirmed | Covered by resource/I/O runbook |
| Alternate deployment created to separate Kubernetes configuration from application startup failure | Confirmed diagnostic pattern | Covered by CrashLoopBackOff workflow |
| `crictl` not available in normal PATH while diagnosing RKE2 static pods | Confirmed diagnostic pitfall | Covered in etcd runbook |

## Linux / systemd / boot

| Case | State | Runbook |
|---|---|---|
| Full root filesystem caused by container JSON logs | Documented | `runbooks/linux/docker-json-log-disk-full.md` |
| Duplicate SSH host keys after VM cloning | Documented | `runbooks/linux/cloned-vm-duplicate-ssh-host-keys.md` |
| Expected generic service missing because software runs as custom multi-instance units | Documented | `runbooks/linux/nonstandard-systemd-service-discovery.md` |
| Runtime configuration discovered from systemd unit/process arguments instead of assumed `/etc` path | Documented | Same runbook |
| UEFI boot entry corruption/duplication repaired while preserving Windows Boot Manager | Documented | `runbooks/linux/uefi-grub-dual-boot-repair.md` |
| Slow Linux boot analyzed with `systemd-analyze`, `blame`, and `critical-chain` | Documented | `runbooks/linux/systemd-analyze-boot-slowness.md` |
| NetworkManager wait-online was on the boot critical path before Docker | Documented diagnostic pattern | Same runbook |
| Shell alias changed `grep` behavior and produced misleading option/encoding errors | Documented diagnostic pitfall | Same runbook |
| Disk usage compared across root, application data, and RKE2 data mounts | Confirmed diagnostic pattern | Resource/I/O runbook |
| Memory pressure differentiated from application failure | Confirmed diagnostic pattern | Resource/I/O runbook |
| OpenMRS `systemd` unit expected but not present | Confirmed older incident | General pattern covered by nonstandard-service discovery |

## Java / Spring Boot / application server

| Case | State | Runbook |
|---|---|---|
| JAR compiled for newer Java class version than host runtime | Documented | `runbooks/java/java-version-and-spring-placeholder-errors.md` |
| Spring placeholder such as `${VAR}` reaches runtime unresolved | Documented | Same runbook |
| JAR launched from sourced environment file with `nohup` and redirected logs | Documented | `runbooks/java/run-jar-with-env-file-and-nohup.md` |
| Java payment transaction rolled back because required `phoneNumber` was null/missing | Documented | `runbooks/java/payment-rollback-missing-required-field.md` |
| Redis property-prefix compatibility (`spring.data.redis.*` vs older naming) | Investigated | Keep application-version specific; no generalized fix claimed |
| Merchant approval ended with application error code after DB lookup and Keycloak-user attempt | Investigated, unresolved | Keep in inventory until response status/source decision path is captured |
| OpenSearch-backed log viewer exited because `OPENSEARCH_PASSWORD` placeholder was unresolved | Confirmed | General unresolved-placeholder pattern already documented |

## Identity / Keycloak

| Case | State | Runbook |
|---|---|---|
| Keycloak start failed because installation/data directory was root-owned while process ran unprivileged | Documented | `runbooks/keycloak/keycloak-data-directory-permission-startup.md` |
| Version-specific Keycloak bootstrap command mismatch distracted from filesystem error | Documented diagnostic pattern | Same runbook |

## Redis / Predixy

| Case | State | Runbook |
|---|---|---|
| Redis Cluster `MOVED` responses | Documented | `runbooks/redis/redis-cluster-moved-and-proxy-auth.md` and Kubernetes MOVED runbook |
| No generic `redis.service`; separate Redis instance units discovered | Documented | `runbooks/linux/nonstandard-systemd-service-discovery.md` |
| Predixy authentication appeared permissive/unexpected | Documented reproduction workflow | `runbooks/redis/predixy-authentication-validation-lab.md` |
| Six-node Redis Cluster lab used to reproduce proxy/auth behavior safely | Documented | Same runbook |
| Predixy `auth.conf`/mount path mismatch | Documented pattern | Same runbook |

## Kafka

| Case | State | Runbook |
|---|---|---|
| KRaft quorum health checked separately from producer/application failure | Documented | `runbooks/kafka/quorum-vs-producer-failure-triage.md` |
| SCRAM authentication rollout and validation | Documented | Existing Kafka runbooks |
| mTLS client authentication with PKCS12/JKS | Documented | Existing Kafka runbooks |
| Java client smoke test from Docker | Documented | `runbooks/kafka/docker-jks-mtls-smoke-test.md` |
| Application log triage for producer, SSL handshake, publishing, and delivery evidence | Documented | Quorum-vs-producer runbook |
| Existing JKS/truststore/keystore discovery for an application migration | In progress | Do not claim a final root cause until validated |

## Databases

| Case | State | Runbook |
|---|---|---|
| Oracle `ORA-00942` caused by schema/object resolution and view discovery | Documented | `runbooks/database/oracle-object-resolution-and-view-inspection.md` |
| Oracle customer lookup failed because phone numbers used inconsistent prefixes/formatting | Documented | `runbooks/database/oracle-phone-number-normalization.md` |
| YugabyteDB YSQL Not Ready / PostgreSQL initialization issue | Documented | `runbooks/database/yugabytedb-ysql-not-ready.md` |
| Flyway migration history inspected to verify actual installed migrations | Documented | `runbooks/database/flyway-migration-history-verification.md` |
| MySQL local socket missing because server startup hit `Permission denied` | Documented investigation; final exact denial source unresolved | `runbooks/database/mysql-socket-permission-denied-startup.md` |
| Oracle client/SQL*Plus connectivity from Ubuntu | Confirmed operational troubleshooting | Generalize further only with complete connection-failure evidence |
| PACS integration marker inspected directly in PostgreSQL during AtomFeed troubleshooting | Confirmed application/database troubleshooting | Await standalone integration runbook |

## Docker / Containers / Registry

| Case | State | Runbook |
|---|---|---|
| Static frontend contained obsolete backend/API endpoint | Documented | `runbooks/docker/patch-static-frontend-inside-image.md` |
| Existing image inspected, patched, verified, committed, and retagged | Documented | Same runbook |
| Custom Predixy image built to reproduce Redis proxy behavior | Documented | Predixy lab runbook |
| Harbor image push returned HTTP 500 while UI/components were otherwise healthy | Documented investigation pattern | `runbooks/docker/harbor-push-http500-object-storage-endpoint.md` |
| S3-compatible object-store console endpoint confused with API endpoint | Documented | Same runbook |

## Observability

| Case | State | Runbook |
|---|---|---|
| Application and Kubernetes/platform logs mixed in one OpenSearch dataset | Documented | `runbooks/observability/opensearch-separate-application-platform-logs.md` |
| Fluent Bit/platform logs appearing in application log views | Documented | Same runbook |
| Legacy OpenSearch data views backed up and removed | Confirmed | Covered by OpenSearch dataset workflow |
| Audit/event timestamp source field validated from actual indexed documents | Documented | `runbooks/observability/opensearch-timestamp-field-validation.md` |
| Prometheus retention shorter than required dashboard/history window | Documented | `runbooks/observability/prometheus-retention-history-window.md` |
| Prometheus rule validation and safe reload | Confirmed | Alert validation runbook |
| Alertmanager/Telegram critical -> resolved lifecycle investigated | Documented | `runbooks/observability/prometheus-alertmanager-telegram-validation.md` |
| Alert message identity improved from raw instance/IP:port to node label | Documented pattern | Same runbook |
| Test alert created and verified absent from both Prometheus and Alertmanager after cleanup | Documented pattern | Same runbook |
| Disk alerts verified against real filesystems while excluding unsuitable pseudo/overlay filesystems | Confirmed | Alert validation/resource runbooks |
| Spring Boot multiline parser validated against real multiline stack traces | Confirmed | Candidate for future dedicated log-pipeline runbook |
| Trace/log correlation proved service aliases while one service had zero correlated logs | Investigated, partly unresolved | Candidate for future OpenTelemetry correlation runbook |
| Heavy dashboard panels reduced to a lightweight wallboard because of machine pressure/clutter | Confirmed operational optimization | Not an incident runbook yet |

## Networking / VPN / messaging endpoints

| Case | State | Runbook |
|---|---|---|
| FortiVPN connection, certificate, routing, and DNS troubleshooting | Documented | `runbooks/networking/fortivpn-certificate-and-dns-troubleshooting.md` |
| SSL certificate SAN inspected with OpenSSL when external VPN endpoint differed from certificate identity | Documented pattern | Same runbook |
| NetworkManager VPN secrets/password flags adjusted on Linux | Documented pattern | Same runbook |
| Windows VPN access-denied reproduction | Investigated, not generalized as resolved | Await stronger evidence before publishing a final fix |
| Repeated SMPP bind/connect timeout with retry loop | Documented investigation pattern; upstream fix not captured | `runbooks/networking/smpp-bind-timeout-network-triage.md` |

## Automation / Ansible / package management

| Case | State | Runbook |
|---|---|---|
| Ansible YAML `ScannerError` caused by malformed inline comment | Documented | `runbooks/automation/ansible-yaml-scanner-error.md` |
| Legacy Ansible `sudo:` attribute incompatibility | Confirmed older parser/playbook issue | Covered as related pattern in YAML runbook |
| Ansible action failed with unexpected boolean parameter type | Confirmed older issue | Needs original task context before standalone runbook |
| `npm` missing during application installation | Confirmed | `runbooks/automation/legacy-nodesource-repository.md` |
| Stale NodeSource/Node.js 10 repository kept producing package 404 after newer repo setup | Documented investigation; final correction not captured | Same runbook |

## Health-system / integration incidents retained for future runbooks

| Case | State | Notes |
|---|---|---|
| ERP connector AtomFeed returned logged 500 while direct endpoint test returned 404 | Investigated | Lab orders later worked; radiology/procedure sync remained the narrowed problem |
| OpenELIS/AtomFeed encounter failed because patient UUID was absent in downstream system | Investigated | POST endpoint test returned method-not-supported; GET path test produced integer conversion failure |
| PACS AtomFeed reported missing last-read entry; marker table inspected and feed reset attempted | Investigated | Processing resumed far enough to expose a later DICOM conversion failure |
| HL7-to-DICOM conversion failed because an expected XSL stylesheet was missing | Investigated, unresolved in retrieved evidence | Strong candidate for a dedicated integration runbook |

## Publication rule

A case is marked **Documented** only when there is enough evidence to describe a repeatable investigation or recovery pattern. Cases still under investigation stay in the inventory but are not presented as solved incidents.
