# UAT to Production Delivery Workflow

This document describes the sanitized operating pattern used to move infrastructure and platform changes from UAT into production for a multi-service banking environment.

> All names, addresses, credentials, certificates, customer identifiers, and capacity values are intentionally omitted.

## Delivery model

The environment was not treated as a single application deployment. Changes could affect Kubernetes, messaging, caching, databases, identity, storage, reverse proxies, observability, or application runtime configuration. Because of that, each change was validated at both the infrastructure layer and the application/business-flow layer.

## Typical workflow

1. **Inspect the current state**
   - confirm active service versions and runtime configuration
   - identify dependent applications and ports
   - check cluster/quorum/replication health where relevant
   - capture the currently working configuration before changing anything

2. **Back up configuration**
   - preserve service configuration files
   - preserve deployment manifests or Rancher/Kubernetes resource definitions
   - preserve database or application configuration when the change affects connectivity
   - prepare rollback commands before the change window

3. **Validate in UAT**
   - apply the change to the UAT environment first
   - verify service startup and health
   - validate network connectivity and authentication
   - verify the application actually loads the intended configuration
   - test the end-to-end business path, not only the service process

4. **Observe before production rollout**
   - review logs, metrics, alerts, storage, and resource usage
   - confirm no hidden clients still depend on the old path
   - compare expected and actual runtime behavior

5. **Roll gradually in production**
   - use rolling changes for clustered services where possible
   - change non-leader/non-critical nodes before the current leader when appropriate
   - verify cluster health between each step
   - keep the old path temporarily during staged migrations when that reduces risk

6. **Validate after each change**
   - service health
   - network listener state
   - quorum/replication status
   - TLS/authentication
   - application connectivity
   - logs and metrics
   - business-flow confirmation

7. **Retire legacy configuration only after migration is proven**
   - remove unused listeners/endpoints
   - remove duplicate or stale application properties
   - keep rollback artifacts for an observation period
   - document the final supported path

## Example: Kafka security migration

The Kafka migration followed the same pattern:

```text
legacy application listener
        |
        | keep available during migration
        v
parallel mTLS listener introduced
        |
        +--> validate broker certificates
        +--> validate client certificates
        +--> migrate one application at a time
        +--> verify consumer/producer runtime behavior
        v
all migrated clients proven healthy
        |
        v
legacy listener retirement planning
```

The goal was to reduce change risk by introducing the secure path in parallel rather than replacing the working listener in one step.

## Example: Kubernetes/RKE2 application change

```text
Configuration / Secret / image / storage change
        |
        v
UAT deployment
        |
        +--> pod health
        +--> application logs
        +--> runtime env/config
        +--> service connectivity
        +--> business path
        v
production rollout
        |
        +--> rollout status
        +--> dependency verification
        +--> metrics/log review
        v
close only after functional verification
```

## Operating principle

A successful restart was never considered sufficient evidence by itself. The change was considered complete only after the application or service demonstrated the expected runtime behavior.
