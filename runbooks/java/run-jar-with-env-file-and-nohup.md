# Run a Java JAR with an Environment File and nohup

This runbook covers a common handoff where a development team provides a JAR plus environment variables and operations must run the service manually on Linux.

## 1. Confirm the required Java version

Ask the development team which Java major version built the application, then verify the server:

```bash
java -version
```

If the JAR was compiled for a newer Java release, startup may fail with `UnsupportedClassVersionError` or a class-file-version mismatch.

## 2. Create an environment file

Example:

```bash
cat > env.sh <<'EOF'
export APP_PORT=8080
export DATABASE_URL='jdbc:postgresql://<db-host>:5432/<db>'
export DATABASE_USER='<user>'
export DATABASE_PASSWORD='<secret>'
export LOG_LEVEL_ROOT='INFO'
EOF
chmod 600 env.sh
```

Use the variable names expected by the application. Do not publish real credentials.

## 3. Load and inspect the environment

```bash
set -a
source ./env.sh
set +a
env | grep -E '^(APP_|DATABASE_|LOG_)'
```

Avoid printing secret values into shared terminal logs when validating production settings.

## 4. Start the JAR

```bash
nohup java -jar app.jar > app.log 2>&1 &
echo $! > app.pid
```

If a specific JDK is required:

```bash
nohup /usr/lib/jvm/<jdk>/bin/java -jar app.jar > app.log 2>&1 &
```

## 5. Validate startup

```bash
ps -fp "$(cat app.pid)"
tail -F app.log
ss -lntp | grep ':<port>\b'
```

## Common failures

### Class file version mismatch

Run the JAR with the correct Java major version or rebuild the application for the installed runtime.

### Unresolved placeholder

Example:

```text
Value: ${APP_LOG_LEVEL}
```

The expected environment variable was not defined or contains an invalid value. Fix the environment rather than passing unrelated application arguments blindly.

### Service dies after logout

Confirm `nohup` redirection and backgrounding were correct. For long-lived managed environments, prefer a systemd unit after the initial manual validation succeeds.
