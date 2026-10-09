# Keycloak startup failure caused by installation directory ownership

## Problem
A Keycloak installation was unpacked or prepared as `root`, then started as a normal service user. Startup failed while trying to create or modify files under the Keycloak data directory.

## Symptoms
- An expected administrative bootstrap command was unavailable for the installed Keycloak version.
- `start-dev` initially surfaced H2/JDBC-related startup errors.
- A later attempt failed with `AccessDeniedException` under the Keycloak `data` directory.
- `ls -l` showed the installation tree owned by `root:root` while Keycloak was being launched as a non-root user.

## Investigation
```bash
java -version
bin/kc.sh --help
ls -ld . data
find . -maxdepth 2 -printf '%u:%g %m %p\n' | head -100
```

The important split is version-specific command syntax versus filesystem ownership. Do not keep changing Keycloak CLI flags when the runtime cannot write its own data directory.

## Recovery
For a development/test installation intentionally owned by the service user:

```bash
sudo chown -R <service-user>:<service-user> /path/to/keycloak
rm -rf /path/to/keycloak/data
```

Then start Keycloak as that user with the version-appropriate administrative bootstrap environment variables or commands.

## Verification
```bash
ps -ef | grep '[k]eycloak'
ss -lntp | grep <keycloak-port>
curl -I http://127.0.0.1:<keycloak-port>/
```

Confirm that new files in `data/` are created by the intended service account.

## Safety
Do not recursively change ownership on a production installation without first confirming the intended systemd `User=`, file ownership model, mounted storage, and package-management expectations.

## Lesson
CLI-version mismatch can distract from a simpler Linux problem: if a Java service runs as an unprivileged user, its writable paths must actually be writable by that user.