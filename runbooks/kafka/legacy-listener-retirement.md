# Legacy Kafka Listener Retirement

This runbook covers the final hardening phase after application traffic has been migrated to a dedicated TLS or mTLS listener.

The objective is not simply to change a default port. The objective is to identify every remaining dependency, preserve broker and controller health, then remove or isolate listeners that no longer need to exist.

## Example transitional state

```text
9092   PLAINTEXT       legacy / internal
9920   PLAINTEXT       legacy / external
18443  SSL + mTLS      application traffic
9275   CONTROLLER      KRaft quorum
```

A possible final design is:

```text
18092  internal / controlled broker or administration traffic
18443  application mTLS
9275   KRaft controller
```

The exact ports are environment decisions. Moving a PLAINTEXT listener from `9092` to another port does not encrypt it; security comes from access control, isolation, and the selected protocol.

## 1. Inventory the active broker configuration

On every broker, record:

```bash
grep -E '^(listeners|advertised.listeners|listener.security.protocol.map|inter.broker.listener.name|controller.listener.names|controller.quorum.voters)=' /path/to/server.properties
```

Do not assume that `9092` is only an application port. It may also be the inter-broker listener, an administration endpoint, or a dependency used by scripts and monitoring.

## 2. Audit active connections

Inspect current TCP sessions on every broker:

```bash
ss -tnp | grep -E ':(9092|9920)\b'
```

A compact view without process details:

```bash
ss -tn | awk '$4 ~ /:(9092|9920)$/ || $5 ~ /:(9092|9920)$/ {print}'
```

Repeat during representative business periods. A single quiet snapshot does not prove that a listener is unused.

## 3. Search client configuration

Audit:

- Kubernetes ConfigMaps and Secrets
- Deployment environment variables
- systemd unit files
- Java properties and YAML
- WildFly configuration
- shell scripts and cron jobs
- monitoring and administration tooling
- load balancers, firewalls, and health checks

Search for both the old port numbers and legacy listener names.

## 4. Separate traffic classes

Classify every remaining connection:

```text
application traffic
broker-to-broker traffic
KRaft controller traffic
administration tooling
monitoring / exporters
migration-only or unknown traffic
```

Unknown traffic is a blocker. Identify the owner before removing the listener.

## 5. Decide the final internal model

There are two common choices.

### Option A — retain a restricted internal PLAINTEXT listener

Use only on a trusted, controlled network segment and protect it with firewall or ACL policy.

```text
internal tools / broker traffic -> restricted internal listener
applications                    -> mTLS listener
controllers                     -> controller listener
```

### Option B — harden internal broker traffic separately

Treat broker-to-broker TLS as its own change. Do not mix it into legacy listener removal unless it has been designed and tested independently.

This keeps failure domains small and rollback clear.

## 6. Prepare the rolling change

Before editing a broker:

1. back up `server.properties`
2. confirm the current KRaft leader
3. verify all expected voters are healthy
4. confirm follower lag is acceptable
5. verify the secure application listener is healthy
6. confirm no required client still depends on the listener being removed

## 7. Roll one broker at a time

Recommended sequence:

1. non-leader broker
2. next non-leader broker
3. current controller leader last

After each restart, verify:

```bash
ss -lntp | grep -E ':(18092|18443|9275)\b'
```

Then check KRaft quorum status and application connectivity before continuing.

Do not proceed to the next broker while the current broker is unhealthy or follower lag is increasing.

## 8. Validate application independence from legacy ports

For migrated applications, prove that runtime bootstrap addresses point only to the secure listener.

Check logs for:

```text
security.protocol = SSL
Cluster ID
consumer group join / producer metadata
partition assignments or successful sends
```

Also confirm that new connections appear on the secure listener and not on the retired legacy port.

## 9. Remove the listener only after observation

A safe sequence is:

```text
migrate clients
    ↓
observe
    ↓
restrict legacy listener access
    ↓
observe again
    ↓
remove legacy listener from one broker
    ↓
rolling validation
    ↓
remove from remaining brokers
```

This is safer than deleting both legacy listeners immediately after the last application migration.

## 10. Post-change checks

Validate:

- all KRaft voters present
- no sustained follower lag
- only intended listener ports are bound
- all approved applications still connect
- no authentication or TLS errors
- producer and consumer flows are healthy
- monitoring and administrative operations still work
- firewall rules match the new listener model

## Rollback

If a required dependency is discovered after removal:

1. stop the rollout
2. restore the previous broker configuration from backup
3. restart only the affected broker
4. confirm it rejoins the quorum
5. restore the required listener temporarily
6. identify and migrate the overlooked dependency before retrying

Do not roll back multiple brokers simultaneously unless cluster recovery requires it.

## Security note

Port changes are not security controls by themselves.

The security improvement comes from:

- encrypting application traffic
- authenticating clients
- verifying broker identities
- reducing exposed listeners
- restricting remaining internal listeners to trusted networks
- maintaining a clear separation between application, broker, and controller traffic
