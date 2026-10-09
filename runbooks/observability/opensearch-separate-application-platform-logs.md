# OpenSearch: Separate Application and Platform Logs

This runbook covers an observability setup where Kubernetes platform logs and application/deployment logs are mixed into one OpenSearch dataset, making Discover/Logs views noisy and confusing.

## Goal

Maintain separate logical views for:

- application namespaces
- Kubernetes/RKE2/platform namespaces

while retaining a common backing index pattern when that is operationally convenient.

## 1. Inspect the current data source

Identify the backing index pattern and the namespace field used by the log shipper.

Example logical model:

```text
logs-v2-*
├── Application Logs
└── Platform Logs
```

Do not delete the source dataset until replacement views are validated.

## 2. Define namespace groups

Application examples:

```text
app-a
app-b
payments
mobile
ussd
```

Platform examples:

```text
kube-system
cert-manager
longhorn-system
cattle-system
monitoring
```

Use environment-appropriate namespace lists rather than hard-coding organization-specific names into reusable scripts.

## 3. Build filtered aliases or datasets

The exact API depends on the OpenSearch/Dashboards version, but the principle is:

- application alias/dataset filters on application namespaces
- platform alias/dataset filters on platform namespaces
- both retain the correct time field

## 4. Validate before switching defaults

Check that:

- application view contains no Fluent Bit, Rancher, Longhorn, cert-manager, or kube-system noise unless intentionally included
- platform view contains the expected cluster/system logs
- timestamps and message fields render correctly
- the default Discover/Logs dataset points to the intended application view

## 5. Diagnose unexpected platform logs in the application view

Inspect the actual namespace field in the document rather than relying on container name alone.

Search examples:

```text
namespace: kube-system
namespace: longhorn-system
container_name: fluent-bit
```

If platform logs still appear, verify whether:

- the filter references the wrong field name
- namespace values differ from the expected list
- an old unfiltered dataset is still selected as the default
- a saved search/dashboard still references the legacy data view

## 6. Cleanup only after validation

Back up the current Dashboards saved objects or data-view definitions before removing legacy views. Remove only objects proven unused.

## Completion criteria

- application logs are isolated from platform logs
- platform logs remain searchable separately
- default Discover/Logs view is intentional
- legacy datasets are backed up before deletion
- dashboards and saved searches no longer reference removed views
