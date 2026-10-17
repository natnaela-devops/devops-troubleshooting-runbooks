# Standardize Kubernetes application logs for OpenSearch with OpenTelemetry

This runbook documents a real migration problem where Spring Boot and Nginx logs arrived in OpenSearch as inconsistent strings or multiline blobs, making cross-service filtering and trace correlation unreliable.

## Symptoms

- Different namespaces emit incompatible field names.
- Stack traces are split or stored as unstructured blobs.
- `trace_id` / `span_id` cannot be used consistently across services.
- Dashboards require service-specific parsing logic.
- Application and proxy logs cannot be queried through one predictable schema.

## Root cause

Applications emitted different formats and the collection pipeline forwarded raw container stdout/stderr without normalizing the records. Dynamic mapping then created inconsistent OpenSearch field types and names.

## Remediation used

### Emit structured JSON from Spring Boot

Services were configured to write JSON rather than free-form console text using a Logback JSON encoder. The goal was a consistent event shape containing fields such as:

```text
timestamp
log.level
service.name
trace_id
span_id
message
```

### Parse and normalize in the collector

OpenTelemetry Collector processors/parsers were used to decode JSON and normalize container log records before forwarding them to OpenSearch. Multiline Java stack traces were handled as one logical event rather than independent lines.

Conceptual pipeline:

```yaml
receivers:
  filelog:
    include:
      - /var/log/pods/*/*/*.log
    operators:
      - type: container
      - type: json_parser
        parse_from: body

processors:
  batch: {}

exporters:
  # OpenSearch/log exporter used by the environment

service:
  pipelines:
    logs:
      receivers: [filelog]
      processors: [batch]
      exporters: [opensearch]
```

Exact receiver/exporter syntax depends on the deployed collector distribution; validate against the installed version.

## Mapping discipline

Before indexing, decide which fields are:

- timestamps;
- keywords/identifiers;
- numeric values;
- searchable message text;
- large raw fields that should not be analyzed.

Do not let inconsistent dynamic mappings accumulate across index generations.

## Validation

Validate with real records from multiple application namespaces and Nginx:

1. one Java exception remains one event;
2. `service.name` is populated consistently;
3. `trace_id` and `span_id` are queryable where the application emitted them;
4. timestamp fields sort correctly;
5. field types remain consistent in newly created indices;
6. dashboards no longer require per-service parsing workarounds.

## Lesson

Observability quality depends on schema quality. A log pipeline is not complete because data reaches OpenSearch; it is complete when the records are structured consistently enough to correlate, filter, aggregate, and alert across services.