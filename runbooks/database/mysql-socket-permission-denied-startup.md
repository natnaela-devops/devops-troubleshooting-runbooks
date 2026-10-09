# MySQL socket connection failure with Permission denied during startup

## Problem
A MySQL client returned an error similar to:

```text
ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/var/run/mysqld/mysqld.sock'
```

Starting the service did not immediately resolve the issue, and the MySQL error log contained `Error: 13 (Permission denied)`.

## Investigation
Do not treat the missing socket as the root cause. The socket is often absent because `mysqld` failed earlier in startup.

```bash
sudo systemctl start mysql
sudo systemctl status mysql --no-pager -l
sudo journalctl -u mysql -n 200 --no-pager
sudo tail -n 200 /var/log/mysql/error.log
sudo ls -ld /var/run/mysqld /var/lib/mysql
sudo namei -l /var/run/mysqld/mysqld.sock
sudo namei -l /var/lib/mysql
```

Inspect ownership and permissions on the runtime and data directories. On distributions using AppArmor or SELinux, also verify whether mandatory-access-control policy is denying the path.

Useful checks:

```bash
sudo dmesg | grep -Ei 'apparmor|denied|mysql|mysqld'
sudo journalctl -k | grep -Ei 'apparmor|denied|mysql|mysqld'
```

## Diagnostic rule
`ERROR 2002` is a client-side symptom. Always read the server startup log before recreating sockets, changing permissions, or reinstalling MySQL.

## Status
In the original incident the startup failure and permission-denied evidence were confirmed, but the exact final permission/AppArmor root cause was not proven. This runbook therefore documents the investigation path without claiming an unverified fix.

## Lesson
Do not manufacture `/var/run/mysqld/mysqld.sock`. Restore the server's ability to start; the socket should then be created by MySQL with the correct ownership and lifecycle.