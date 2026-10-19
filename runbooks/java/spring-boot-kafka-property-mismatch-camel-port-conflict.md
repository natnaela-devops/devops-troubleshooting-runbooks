# Spring Boot Kafka property mismatch and Camel Netty port conflict

## Incident summary

A Java 21 / Spring Boot 3.5.3 service failed to start in UAT. Two separate startup blockers were identified and addressed:

1. A custom Kafka producer bean referenced `kafka.bootstrap.servers`, but the packaged YAML defined only `spring.kafka.bootstrap.servers`.
2. Once the Kafka placeholder was supplied, Apache Camel's Netty HTTP listener could not bind because the intended port was already occupied by another Java process.

**Observed outcome:** The service subsequently started successfully, Camel started all 15 routes, the Kafka producer discovered the broker cluster, and the HTTP listener responded. **End-to-end transaction processing and Kafka message delivery were not demonstrated by this evidence.**

> Sanitized case study: names, hosts, addresses and credentials are omitted or replaced with examples. Do not copy illustrative endpoints into a live environment.

## Symptoms and evidence

Initial failure:

```text
BeanCreationException: Error creating bean with name 'kafkaProducer'
Caused by: PlaceholderResolutionException:
Could not resolve placeholder 'kafka.bootstrap.servers'
in value "${kafka.bootstrap.servers}"
```

Application YAML supplied a *different* property path:

```yaml
spring:
  kafka:
    bootstrap:
      servers: ${IPS_KAFKA_SERVERS}
```

The variable itself was populated, so the failure was **property-name mismatch**, not evidence of missing broker addresses or broker outage. `spring.kafka.bootstrap.servers` and `kafka.bootstrap.servers` are independent property keys.

### Temporary workaround (no JAR modification)

After sourcing the existing environment file, supply the custom property as a command-line argument:

```bash
source ./service_env.sh
java -jar app.jar --kafka.bootstrap.servers="$IPS_KAFKA_SERVERS"
```

The original UAT launch used `nohup` and output redirection for detached execution; those mechanics were unrelated to the configuration fix. This workaround makes Spring resolve the exact property requested by the custom bean and should not be treated as the permanent source fix.

With Kafka configuration resolved, a second issue became visible:

```text
Apache Camel Netty: ServerBootstrap binding to 0.0.0.0:<application-port>
java.net.BindException: Address already in use
```

An existing, root-owned Java process running the same JAR was found on the host. Its termination required elevated privileges. After it was terminated, a fresh launch no longer hit the bind conflict. **Do not terminate an unknown process solely from a filename match:** verify ownership, listener PID and service manager first.

## Safe triage sequence

```bash
# Inspect the actual listener and identify its owner.
sudo ss -lntp | grep ':<application-port>'
ps -ef | grep '[j]ava'

# Confirm the environment variable is set without exposing secrets.
test -n "$IPS_KAFKA_SERVERS" && echo "Kafka bootstrap variable is set"

# Inspect startup logs for the specific failure.
grep -Ei 'PlaceholderResolutionException|BindException|Application run failed' logs/app.log
```

For Camel's Netty HTTP component, changing `server.port` may have no effect; check the application's actual route/listener configuration.

## Verification observed after recovery

- Process remained running as the non-root application user.
- TCP listener was bound to the expected port by the new Java PID.
- GET on `/` returned **HTTP 404**, consistent with a responsive server that has no root route; this is not a payment/API readiness check.
- No `ERROR`, `Exception`, or `Failed` lines were found in the sampled current startup log.
- PostgreSQL connection was established, and Flyway validated three migrations with schema version 3.
- Kafka producer loaded the broker list and logged a cluster ID: **cluster discovery, not proven message delivery**.
- Quartz started; Apache Camel reported **15 routes started**, including four REST-DSL routes.
- Spring Boot reported successful application startup.

## Permanent corrective action

Preserve the standard Spring Kafka key where framework components may rely on it, and supply the separately required custom key, sourced from the same variable:

```yaml
spring:
  kafka:
    bootstrap:
      servers: ${IPS_KAFKA_SERVERS}

# Referenced by the application's custom producer bean.
kafka:
  bootstrap:
    servers: ${IPS_KAFKA_SERVERS}
```

Alternatively, the development team can standardize code on the Spring Kafka property if its wiring supports that change. Do not remove `spring.kafka.bootstrap.servers` without confirming whether other components use it. Release the change via the normal source/build pipeline and test startup **without** the CLI override.

Also confirm how the legacy instance is launched (for example, systemd) to avoid a second listener reclaiming the same port. Use a managed service for reliable restarts instead of relying on interactive `nohup` sessions.

## Follow-up checks

- Exercise approved, non-destructive application endpoints and validate expected responses.
- Confirm Kafka publishing and any consuming behavior through safe integration tests.
- Review producer `enable.idempotence=false` and `security.protocol=PLAINTEXT` against the required reliability/security design; do not change Kafka authentication settings without coordinating the cluster/client configuration.
- Keep secret-bearing environment files private, and never commit them.
- Distinguish **startup recovered** from **complete business-flow validation**.

## Lessons

- Spring property paths must match what a custom `@Value` or configuration binding requests.
- Fix one startup blocker and rerun: the next fault may only appear later in initialization.
- An HTTP 404 can establish listener responsiveness but not health of business routes.
- Verify the listening process before stopping services on shared UAT hosts.
