# Java Runtime Version and Spring Placeholder Troubleshooting

This runbook covers two common failures when running a developer-supplied Spring Boot JAR manually on Linux.

## 1. `UnsupportedClassVersionError`

Typical symptom:

```text
class file version 65.0 ... runtime only recognizes up to 61.0
```

Useful mapping:

| Class file | Java |
|---:|---:|
| 61 | 17 |
| 65 | 21 |

Check the default runtime:

```bash
java -version
```

List installed JDKs:

```bash
ls -1 /usr/lib/jvm/
```

Run the JAR explicitly with the required runtime instead of immediately changing the system default:

```bash
/usr/lib/jvm/java-21-openjdk-amd64/bin/java -jar application.jar
```

This is safer on shared hosts where other services may depend on the current default Java version.

## 2. Spring Boot fails to bind an unresolved environment placeholder

Typical failure:

```text
Failed to bind properties under 'logging.level.root'
Value: "${APP_LOG_LEVEL_ROOT}"
No enum constant org.springframework.boot.logging.LogLevel.${APP_LOG_LEVEL_ROOT}
```

The application configuration contains a placeholder such as:

```yaml
logging:
  level:
    root: ${APP_LOG_LEVEL_ROOT}
```

but the environment variable is missing.

Set a valid value before starting the application:

```bash
export APP_LOG_LEVEL_ROOT=INFO
java -jar application.jar
```

Valid Spring Boot log levels normally include:

```text
TRACE DEBUG INFO WARN ERROR FATAL OFF
```

## 3. Inspect application configuration inside a JAR

```bash
unzip -p application.jar BOOT-INF/classes/application.yaml | sed -n '1,220p'
```

or:

```bash
unzip -p application.jar BOOT-INF/classes/application.properties | sed -n '1,220p'
```

Search for placeholders:

```bash
unzip -p application.jar BOOT-INF/classes/application.yaml | grep -o '\${[^}]*}' | sort -u
```

## 4. Use an environment file for repeatable starts

Example `env.sh`:

```bash
export APP_LOG_LEVEL_ROOT=INFO
export SPRING_PROFILES_ACTIVE=uat
export DATABASE_URL='jdbc:postgresql://db.example:5432/app'
```

Load it:

```bash
source ./env.sh
```

Then start the service:

```bash
nohup java -jar application.jar > application.log 2>&1 &
```

## Completion checks

```bash
ps -ef | grep '[j]ava.*application.jar'
tail -f application.log
```

The application should start without class-version or unresolved-placeholder errors.
