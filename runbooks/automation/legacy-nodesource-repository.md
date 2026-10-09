# Legacy NodeSource repository causes npm/Node.js installation failures

## Problem
An Ansible-driven application installation required `npm`, but Node.js installation repeatedly failed because the host still referenced an obsolete NodeSource repository/package generation.

## Symptoms
- `npm` was missing.
- Repository cleanup/setup was attempted for a newer Node.js release.
- `yum install nodejs` continued trying to resolve an old Node.js `10.x` package.
- The package URL returned HTTP `404` over HTTPS.

## Investigation
First identify every repository definition and cached metadata source instead of repeatedly rerunning the installer:

```bash
rpm -qa | grep -Ei 'node|nodesource'
yum repolist all | grep -i node
grep -RniE 'nodesource|node_[0-9]+|10\.x' /etc/yum.repos.d/
yum clean all
rm -rf /var/cache/yum
```

Check package candidates and repository provenance:

```bash
yum list nodejs --showduplicates
yum info nodejs
```

## Recovery pattern
1. Remove or disable stale NodeSource repository definitions.
2. Clear cached metadata.
3. Install the repository configuration for the intended supported Node.js version.
4. Confirm `yum` sees the expected package before rerunning Ansible.

## Verification
```bash
node --version
npm --version
yum info nodejs
```

Then rerun only the failed installation role/task if possible rather than the entire deployment.

## Status
The original investigation proved that stale repository metadata/configuration was still pulling the obsolete package and that the referenced package URL no longer existed. The final repository correction was not captured, so this runbook documents the confirmed troubleshooting path without claiming a resolved state.

## Lesson
Changing the repository setup script does not guarantee the package manager stopped using old repository definitions or cached metadata. Verify the package candidate before blaming Ansible.