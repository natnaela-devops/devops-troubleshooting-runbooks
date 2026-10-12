# Banking Digital Platform Infrastructure — Production Case Study

This page is the recruiter-facing entry point to a sanitized record of hands-on DevOps/SRE work performed across **UAT and production banking environments**.

The environment combined Kubernetes-hosted and VM-hosted services across platform operations, identity, messaging, caching, databases, storage, observability, artifact delivery, and secure reverse proxying.

## Platform scope

- **RKE2 + Rancher** for Kubernetes platform operations
- **Longhorn** for persistent Kubernetes storage
- **Harbor** for private container images
- **Kafka/KRaft** as a multi-node messaging cluster, including a staged migration to application-facing mTLS
- **Redis Cluster + Predixy** for distributed caching and cluster-aware application access
- **YugabyteDB** as a distributed SQL cluster
- **TimescaleDB/PostgreSQL** for supporting application and identity workloads
- **Keycloak** for identity services across separate product boundaries
- **Nginx** for TLS termination, reverse proxying, and secure exposure of API, mobile, web, merchant, receipt/evidence, and identity endpoints
- **SeaweedFS** for receipt/image storage workflows
- **PM2** for selected Node.js frontend/backoffice processes
- **OpenSearch** for centralized logging and operational analysis
- **Prometheus + Alertmanager** for monitoring and alerting
- **OpenTelemetry** integration where applicable

## High-level flow

```text
Mobile / Web / Merchant users
            |
            v
      Nginx / TLS edge
            |
   +--------+---------+----------------+
   |                  |                |
   v                  v                v
APIs / gateways   Web frontends    Keycloak / identity
   |                                   |
   v                                   v
RKE2 / Rancher platform            TimescaleDB
   |
   +--> Kafka / KRaft
   +--> Predixy --> Redis Cluster
   +--> YugabyteDB
   +--> TimescaleDB
   +--> Longhorn-backed workloads
   |
   +--> OpenSearch
   +--> Prometheus --> Alertmanager

Harbor --> RKE2 image delivery
Nginx --> receipt/evidence endpoints --> SeaweedFS
PM2-managed frontends --> Nginx
```

## What I personally worked on

The work included platform setup and operations, service integration, secure reverse-proxy configuration, Kubernetes workload and storage operations, Kafka/Redis cluster readiness, database/service connectivity, observability, certificate and authentication hardening, incident troubleshooting, and UAT-to-production validation.

A representative security migration was the Kafka rollout from legacy PLAINTEXT application access to a parallel **TLS listener with mandatory client certificates**, performed with rolling broker changes, per-application identities, runtime validation, and rollback safety.

## Operating approach

Typical changes followed this pattern:

1. inspect the live configuration and dependencies
2. back up before editing
3. validate in UAT
4. test infrastructure health and application behavior separately
5. prepare rollback steps
6. roll production changes gradually
7. verify quorum/replication, logs, runtime configuration, client connectivity, and business flow
8. retire legacy paths only after all consumers are confirmed migrated

## Detailed documentation

- [Full banking platform case study](projects/banking-digital-platform-infrastructure/README.md)
- [Layered architecture](projects/banking-digital-platform-infrastructure/architecture.md)
- [Kafka mTLS migration architecture](runbooks/kafka/kafka-mtls-migration-architecture.md)
- [Kafka rolling mTLS rollout](runbooks/kafka/kraft-rolling-mtls-listener-rollout.md)
- [Redis Cluster + Predixy architecture](runbooks/redis/redis-cluster-predixy-architecture.md)
- [RKE2 control-plane troubleshooting](runbooks/kubernetes/rke2-control-plane-resource-io-degradation.md)
- [OpenSearch application/platform log separation](runbooks/observability/opensearch-separate-application-platform-logs.md)

## Evidence boundary

This is intentionally sanitized. It does **not** publish customer names, production IP addresses, DNS names, credentials, certificates, private keys, keystores, proprietary source code, production data, or unverified uptime/performance claims.
