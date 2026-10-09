# Prometheus + Alertmanager Telegram Alert Validation

This runbook covers validating a Prometheus/Alertmanager Telegram route without leaving test alerts behind or producing confusing alert messages.

## 1. Validate configuration before reload

Prometheus:

```bash
promtool check config /etc/prometheus/prometheus.yml
promtool check rules /etc/prometheus/rules/*.yml
```

Alertmanager:

```bash
amtool check-config /etc/alertmanager/alertmanager.yml
```

Use the paths installed in your environment.

## 2. Keep messages operationally clear

A useful message should identify:

- firing vs recovered state
- severity
- alert name
- environment
- team/service
- node or instance
- filesystem/mountpoint when relevant

Prefer a real node label over an exporter `host:port` value when both exist.

## 3. Use a temporary validation alert

Create a clearly named rule, for example:

```yaml
- alert: TelegramFormatValidation
  expr: vector(1)
  for: 0m
  labels:
    severity: warning
    environment: test
    team: infrastructure
  annotations:
    summary: Telegram formatting validation
```

Reload Prometheus through the supported mechanism and confirm the message reaches Telegram.

## 4. Remove the test rule after validation

Delete the temporary alert, re-run `promtool`, and reload Prometheus again.

Then verify the test alert is gone from both systems:

```bash
curl -s http://127.0.0.1:9090/api/v1/alerts | jq .
curl -s http://127.0.0.1:9093/api/v2/alerts | jq .
```

Do not leave permanent validation alerts firing in a real environment.

## 5. Understand firing followed by resolved

A critical alert followed minutes later by a recovery message does not necessarily mean Alertmanager is unstable. Check whether the Prometheus expression actually returned to a healthy value and whether the `for:` duration was satisfied.

## 6. Disk-alert checks

For filesystem alerts, explicitly exclude ephemeral/virtual filesystems where appropriate and preserve labels needed to identify the affected node and mountpoint.

Example useful dimensions:

```text
node
instance
mountpoint
device
environment
severity
```

## Completion criteria

- Prometheus rules validate
- Alertmanager config validates
- Telegram receives firing and recovered formats correctly
- test alert is removed afterward
- Prometheus and Alertmanager APIs contain no leftover validation alert
