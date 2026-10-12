# Kafka mTLS Migration Architecture

This runbook explains a safe migration from legacy PLAINTEXT Kafka listeners to a dedicated mutual-TLS application listener in a three-node KRaft cluster.

> The examples are intentionally generic. Replace addresses, ports, certificate names, and paths with values appropriate to your environment.

## Starting point

A common legacy layout looks like this:

```text
Applications
    |
    | PLAINTEXT
    v
Kafka brokers
    |
    +-- client listener :9092
    +-- legacy/external listener :9920
    +-- KRaft controller listener :9275
```

The application path is functional, but client traffic is not protected by TLS and clients do not authenticate with certificates.

## Migration principle

Do not replace the legacy listener first. Add a new secure listener in parallel so existing workloads remain available while applications are migrated one at a time.

```text
Phase 1
legacy client listeners only

        ↓

Phase 2
legacy listeners + dedicated mTLS listener

        ↓

Phase 3
all approved applications on mTLS

        ↓

Phase 4
retire unused legacy listeners
```

This provides a practical rollback boundary during the migration.

## Target application architecture

```text
                  Kafka internal CA
                        |
          +-------------+-------------+
          |             |             |
      broker-1      broker-2      broker-3
      server cert   server cert   server cert
          ^             ^             ^
          |             |             |
          +-------------+-------------+
                        |
                   mTLS :18443
                        |
         +--------------+--------------+
         |              |              |
      app-a cert      app-b cert     app-c cert
         |              |              |
      app-a           app-b          app-c
```

The broker verifies that the client certificate is signed by a trusted CA. The client verifies the broker certificate and its SAN.

## PKI model

Use one internal Kafka CA and separate identities for brokers and logical applications.

```text
Kafka CA
├── broker-1 certificate      serverAuth
├── broker-2 certificate      serverAuth
├── broker-3 certificate      serverAuth
├── application-a certificate clientAuth
├── application-b certificate clientAuth
└── application-c certificate clientAuth
```

Operational rules:

- keep the CA private key only on the designated signing host
- issue one broker certificate per node
- include the DNS names or IP addresses actually used by clients in broker SANs
- issue one client identity per logical application instead of sharing one identity across unrelated applications
- validate `serverAuth` and `clientAuth` extended-key usage as appropriate

## Broker listener model

During migration, a broker can expose both legacy and secure listeners:

```properties
listeners=PLAINTEXT://0.0.0.0:9092,EXTERNAL://0.0.0.0:9920,MTLS://0.0.0.0:18443,CONTROLLER://0.0.0.0:9275
advertised.listeners=PLAINTEXT://broker-1.example:9092,EXTERNAL://broker-1.example:9920,MTLS://broker-1.example:18443
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,EXTERNAL:PLAINTEXT,MTLS:SSL,CONTROLLER:PLAINTEXT
ssl.keystore.location=/etc/kafka/ssl/broker.p12
ssl.keystore.type=PKCS12
ssl.truststore.location=/etc/kafka/ssl/truststore.p12
ssl.truststore.type=PKCS12
ssl.client.auth=required
ssl.enabled.protocols=TLSv1.2,TLSv1.3
```

The exact listener names are design choices. The important point is that the application-facing listener maps to `SSL` and requires a trusted client certificate.

## Rolling broker rollout

Do not restart every broker together.

1. Back up the active Kafka configuration.
2. Verify KRaft quorum health before making changes.
3. Add the new listener and TLS material to one non-leader broker.
4. Restart only that broker.
5. Confirm all expected listeners are bound.
6. Recheck quorum voters and follower lag.
7. Validate the new TLS listener independently.
8. Repeat for the next non-leader broker.
9. Roll the current controller leader last.
10. Verify the full quorum again before migrating applications.

Healthy quorum evidence should include all expected voters and no sustained follower lag.

## Validate transport before application configuration

Use a direct TLS client test before debugging Java or Spring settings.

A successful direct test should prove:

- network reachability
- broker listener availability
- CA trust
- client certificate acceptance
- broker certificate verification
- hostname or IP SAN verification
- negotiated TLS version

This separates infrastructure problems from application configuration problems.

## Application migration

For each application:

1. create or validate its client certificate
2. build the required PKCS12 or JKS keystore
3. build a truststore containing the Kafka CA
4. mount the stores into the runtime
5. inject passwords through a secret mechanism
6. change bootstrap servers to the mTLS listener
7. set `security.protocol=SSL`
8. enable endpoint identification when broker SANs are correct
9. restart only that application
10. validate runtime Kafka properties, not just source configuration
11. confirm cluster metadata, producer/consumer operation, and business flow

Do not assume all frameworks interpret `file:/path` and `/path` identically. Use the path form proven by the application's runtime behavior.

## Kubernetes / RKE2 clients

A typical PKCS12 client mount is:

```text
/etc/kafka-certs/client-keystore.p12
/etc/kafka-certs/truststore.p12
```

A JKS-based application may instead use:

```text
/etc/kafka-certs/kafka.keystore.jks
/etc/kafka-certs/kafka.truststore.jks
```

For Rancher-managed Secrets, verify binary files by SHA-256 after mounting. A valid Kubernetes Secret definition does not by itself prove that a binary keystore survived encoding and mounting correctly.

## Successful end state

The secure application path becomes:

```text
Application
    |
    | load client keystore
    | load CA truststore
    v
TLS handshake
    |
    +-- client verifies broker certificate
    +-- broker verifies client certificate
    v
Kafka mTLS listener
    |
    v
Kafka metadata
    |
    v
partition leaders across the cluster
```

The bootstrap list is only for discovery. After metadata is fetched, the client communicates with the brokers that lead the relevant partitions.

## Completion criteria

A migration is not complete merely because port `18443` is reachable.

Require evidence that:

- every broker accepts valid mTLS clients
- clients without a valid certificate are rejected
- hostname/IP verification succeeds
- KRaft quorum remains healthy through the rolling change
- migrated applications load the intended runtime SSL configuration
- producers and consumers obtain cluster metadata
- consumer groups join and receive assignments where applicable
- business transactions or messages complete successfully
- legacy listeners are no longer used by migrated applications

## Next phase

Once all approved workloads have operated successfully on mTLS for an agreed observation period, audit the remaining legacy listeners and retire or isolate them using the procedure in [Legacy Kafka Listener Retirement](legacy-listener-retirement.md).
