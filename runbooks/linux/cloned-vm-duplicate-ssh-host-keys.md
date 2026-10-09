# Cloned VM Duplicate SSH Host Keys

This runbook covers a common VM cloning problem where multiple Linux guests inherit the same SSH host keys and therefore present the same host fingerprint.

> Use placeholders for hostnames and addresses. Never publish real private infrastructure identifiers.

## Symptoms

- two or more cloned VMs show the same SSH host fingerprint
- `ssh` warns that the remote host identification changed
- a known-host entry for one clone collides with another

## Confirm the fingerprints

Run on each VM:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

If all clones report the same fingerprint, regenerate the host keys.

## Regenerate SSH host keys

On each clone independently:

```bash
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A
systemctl restart ssh || systemctl restart sshd
```

Verify again:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Each VM should now have a unique fingerprint.

## Clean stale client entries

From the administration workstation:

```bash
ssh-keygen -R <host-or-ip>
```

Reconnect and verify the new fingerprint before accepting it.

## Notes

Cloned systems may also duplicate `/etc/machine-id`. Treat that as a separate clone-hygiene task; do not change it during an unrelated production incident unless the duplicate identity is actually causing a problem.
