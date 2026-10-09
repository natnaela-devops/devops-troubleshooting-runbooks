# Ansible YAML ScannerError caused by malformed inline comments

## Problem
An Ansible-based application installation failed before executing tasks because the YAML configuration could not be parsed.

## Symptom
Typical failure:

```text
ScannerError: mapping values are not allowed here
```

The failing line contained a value and comment without the required whitespace, for example:

```yaml
selinux_state: disabled# comment
```

## Investigation
Validate YAML syntax independently before debugging Ansible roles, package repositories, or remote hosts.

```bash
python3 - <<'PY'
import yaml
with open('/path/to/setup.yml') as f:
    yaml.safe_load(f)
print('YAML OK')
PY
```

If PyYAML is unavailable, use Ansible's own syntax check where applicable:

```bash
ansible-playbook --syntax-check <playbook>.yml
```

Inspect the exact line and nearby indentation:

```bash
nl -ba /path/to/setup.yml | sed -n '<start>,<end>p'
```

## Fix
Separate inline comments from YAML scalar values correctly:

```yaml
selinux_state: disabled  # comment
```

or place the comment on its own line.

## Related parser mistakes
Older Ansible content can also fail because parameters valid in one generation are invalid in another. For example, legacy `sudo:` play attributes may need to be replaced with supported privilege-escalation syntax such as `become:`.

## Verification
Run syntax validation first, then rerun the playbook with controlled verbosity:

```bash
ansible-playbook --syntax-check <playbook>.yml
ansible-playbook <playbook>.yml -vv
```

## Lesson
When Ansible says YAML cannot be parsed, do not troubleshoot the target service yet. The automation never reached the target; fix the document structure first.