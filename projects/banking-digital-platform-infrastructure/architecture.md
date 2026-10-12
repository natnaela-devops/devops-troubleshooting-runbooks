# Architecture Notes

This document expands the generalized architecture used in the banking-platform case study. It is intentionally environment-neutral.

## Layered view

```text
Users / Channels
      |
      v
Nginx TLS + Reverse Proxy
      |
      +--> API / Gateway routes
      +--> WebView / Merchant / Backoffice routes
      +--> Keycloak identity endpoints
      +--> Receipt / evidence endpoints

Application Platform
      |
      +--> RKE2 + Rancher
      |      +--> application deployments
      |      +--> Services / ConfigMaps / Secrets
      |      +--> Longhorn-backed persistent workloads
      |
      +--> PM2-managed frontend processes where not containerized

Shared Platform Services
      |
      +--> Kafka KRaft cluster
      +--> Redis Cluster via Predixy
      +--> YugabyteDB cluster
      +--> TimescaleDB / PostgreSQL
      +--> SeaweedFS
      +--> Harbor registry

Observability
      |
      +--> Prometheus
      +--> Alertmanager
      +--> OpenSearch
      +--> OpenTelemetry integration
```

## Traffic responsibilities

### Nginx

Nginx served as the controlled edge layer for selected domains and application routes. Responsibilities included TLS termination, reverse proxying, gateway exposure, identity endpoints, receipt/evidence access, web-facing routes, and product-specific domain separation.

### RKE2

RKE2 hosted containerized banking services. Rancher provided the operational UI for workload and cluster administration. Longhorn supported persistent workloads requiring replicated storage inside Kubernetes.

### Kafka

Kafka provided asynchronous messaging between services. The cluster used KRaft quorum. Application connectivity was hardened by introducing a parallel mTLS listener, migrating clients incrementally, and retaining legacy listeners only during the transition window.

### Redis + Predixy

Redis operated as a multi-node cluster with master/replica roles. Predixy provided the stable application-facing entry point and routed requests to the appropriate Redis node while preserving the cluster model behind the proxy.

### YugabyteDB and TimescaleDB

YugabyteDB provided distributed SQL for workloads requiring a clustered database layer. TimescaleDB/PostgreSQL supported standalone relational/time-series workloads and selected supporting services such as identity data.

### SeaweedFS

SeaweedFS supported file/object-style storage requirements such as transaction receipts and related evidence assets.

### Harbor

Harbor provided an internal container-image registry for application delivery into Kubernetes environments.

### OpenSearch + Prometheus

OpenSearch provided centralized log/observability workflows. Prometheus collected infrastructure and service metrics, with Alertmanager handling alert delivery. Application and platform logs were separated to keep troubleshooting views operationally useful.

## UAT and production

UAT was used to validate configuration, connectivity, security changes, and application compatibility before production rollout. Production changes were performed with backups, explicit rollback planning, staged migration, and service-level verification.

The production architecture did not simply replicate UAT node-for-node; capacity, placement, and service separation were adjusted according to environment needs and available resources.
