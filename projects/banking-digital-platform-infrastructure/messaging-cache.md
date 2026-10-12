# Messaging and Cache Layer

This document summarizes the sanitized Kafka and Redis architecture used by the banking platform.

## Kafka / KRaft

Kafka ran as a multi-node KRaft cluster. Application clients used Kafka for asynchronous messaging and event-driven integration between services.

The production hardening work included migrating application traffic from legacy PLAINTEXT listeners to a parallel mTLS listener with mandatory client certificates.

```mermaid
flowchart LR
    App1[Application A]
    App2[Application B]
    K1[Kafka Broker 1]
    K2[Kafka Broker 2]
    K3[Kafka Broker 3]

    App1 -->|mTLS| K1
    App1 -->|mTLS| K2
    App1 -->|mTLS| K3
    App2 -->|mTLS| K1
    App2 -->|mTLS| K2
    App2 -->|mTLS| K3
    K1 <--> K2
    K2 <--> K3
    K3 <--> K1
```

Validation included:

- KRaft quorum state
- listener health
- broker certificates and SANs
- client certificates
- PKCS12/JKS store integrity
- application runtime properties
- producer/consumer connectivity
- consumer-group joins and assignments
- partition-leader communication across brokers

## Redis Cluster + Predixy

Redis used a clustered master/replica topology. Predixy provided a stable application-facing endpoint and cluster-aware routing layer.

```mermaid
flowchart LR
    App[Application]
    P[Predixy]
    M1[Redis Master 1]
    M2[Redis Master 2]
    M3[Redis Master 3]
    R1[Replica 1]
    R2[Replica 2]
    R3[Replica 3]

    App --> P
    P --> M1
    P --> M2
    P --> M3
    M1 --> R1
    M2 --> R2
    M3 --> R3
```

Operational work included:

- validating Redis Cluster state and slot ownership
- handling `MOVED` behavior correctly
- checking proxy routing through Predixy
- validating Redis authentication in the application path
- distinguishing Redis-node health from proxy or application configuration issues

## Design distinction

Kafka bootstrap addresses are discovery seeds. After metadata retrieval, Kafka clients communicate with the broker responsible for the required partition.

Predixy is different: it remains in the Redis request path and routes application operations to the correct Redis node.

## Safety boundaries

No production broker addresses, Redis passwords, client certificates, keystores, cluster IDs, or application-specific secrets are included in this public case study.
