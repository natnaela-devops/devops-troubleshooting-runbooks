# Run Keycloak reliably with systemd

This runbook documents a real Keycloak service-management failure pattern: Keycloak worked when launched interactively with `kc.sh`, but stopped when the SSH session ended or failed during boot because the runtime environment, Java path, permissions, and service limits were not defined consistently.

## Symptoms

- Keycloak starts manually but disappears after logout.
- `systemctl start keycloak` fails although `kc.sh start` works in a shell.
- Logs show missing Java/runtime paths or permission errors under the Keycloak installation/data directories.
- The service is unstable under sustained authentication traffic.

## Root cause

An interactive shell supplies environment variables and session lifetime implicitly. systemd does not. The service therefore needs an explicit Java runtime, Keycloak configuration path, service user, restart behavior, and ownership of the directories it must write to.

## Service account and ownership

Use a dedicated non-root account:

```bash
sudo useradd --system --home /opt/keycloak --shell /usr/sbin/nologin keycloak
sudo chown -R keycloak:keycloak /opt/keycloak
```

Do not recursively change ownership of unrelated system paths. Limit ownership changes to the Keycloak installation/data locations that the service actually needs.

## Example unit

```ini
[Unit]
Description=Keycloak Identity Provider
After=network.target

[Service]
Type=simple
User=keycloak
Group=keycloak
Environment="JAVA_HOME=/usr/lib/jvm/java-21-openjdk"
Environment="KC_CONFIG_FILE=/opt/keycloak/conf/keycloak.conf"
ExecStart=/opt/keycloak/bin/kc.sh start --optimized
TimeoutStartSec=600
LimitNOFILE=65536
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
```

The Java path and Keycloak options are version/environment specific; verify them on the target host rather than copying them blindly.

## Apply and inspect

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now keycloak
sudo systemctl status keycloak --no-pager
sudo journalctl -u keycloak -n 200 --no-pager
```

If startup still fails, compare the environment of the successful interactive command with the unit configuration and check filesystem access:

```bash
namei -l /opt/keycloak
sudo -u keycloak test -r /opt/keycloak/conf/keycloak.conf && echo readable
sudo -u keycloak test -w /opt/keycloak/data && echo writable
```

## Validation

A successful fix is not only `systemctl active`. Validate that Keycloak survives logout/reboot, listens on the expected socket, and serves a health or login endpoint through the real reverse-proxy path.

## Lesson

When a Java service works manually but not under systemd, compare execution context before changing the application itself: user, group, environment, working paths, permissions, limits, and process lifecycle.