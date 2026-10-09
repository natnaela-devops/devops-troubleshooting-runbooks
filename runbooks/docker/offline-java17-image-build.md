# Build a Java 17 Docker Application Image on an Offline Host

This runbook covers building a Java 17 application image on a Docker host that has no internet access.

The key idea is simple: prepare the Java base image on an internet-connected machine, export it as a tar archive, transfer it to the offline host, load it into Docker, and then build the application image locally.

## 1. Prepare the Java 17 base image on an internet-connected machine

Pull a small Java 17 runtime image:

```bash
docker pull eclipse-temurin:17-jre-alpine
```

Export it:

```bash
docker save -o eclipse-temurin-17-jre-alpine.tar eclipse-temurin:17-jre-alpine
```

Record its checksum before transfer:

```bash
sha256sum eclipse-temurin-17-jre-alpine.tar
```

## 2. Transfer the image archive to the offline host

Example:

```bash
scp eclipse-temurin-17-jre-alpine.tar <user>@<offline-host>:/tmp/
```

Transfer the checksum separately or compare the previously recorded value after copying.

## 3. Verify the archive on the offline host

```bash
sha256sum /tmp/eclipse-temurin-17-jre-alpine.tar
```

Do not continue if the checksum differs from the source machine.

## 4. Load the base image into Docker

```bash
docker load -i /tmp/eclipse-temurin-17-jre-alpine.tar
```

Verify:

```bash
docker images | grep eclipse-temurin
```

Optionally confirm the runtime:

```bash
docker run --rm eclipse-temurin:17-jre-alpine java -version
```

## 5. Prepare the application Dockerfile

Example:

```dockerfile
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

COPY application.jar /app/app.jar

EXPOSE 8989

ENTRYPOINT ["java","-jar","/app/app.jar"]
```

Avoid placeholder characters such as `<...>` in a real `COPY` instruction. The source filename must exist in the Docker build context.

Suggested directory:

```text
application/
├── Dockerfile
├── application.jar
├── docker-compose.yml
└── .env
```

## 6. Build the application image offline

Once the base image has been loaded locally, Docker does not need internet access for this build unless the Dockerfile includes other network-dependent steps.

```bash
docker build -t application:local .
```

Verify:

```bash
docker images | grep application
```

## 7. Keep runtime credentials and certificates out of the image

Do not bake environment secrets, private keys, JKS/PKCS12 stores, or production configuration into the image.

Prefer runtime injection:

```yaml
services:
  application:
    image: application:local
    env_file:
      - ./.env
    volumes:
      - /secure/client-certs:/etc/client-certs:ro
```

Protect the environment file:

```bash
chmod 600 .env
```

## 8. Validate Compose before deployment

```bash
docker compose config
```

Be careful: rendered Compose output can contain resolved secrets. Do not paste it into public repositories or tickets without sanitizing it.

Start only the service being changed when performing a staged migration:

```bash
docker compose up -d <service-name>
```

This reduces blast radius and keeps unrelated services unchanged while the new image is being validated.

## Common failures

### `pull access denied` or network timeout during build

The required base image was not loaded locally, or the `FROM` tag does not exactly match the loaded image tag.

Check:

```bash
docker images
```

### `COPY failed` / source file not found

The JAR filename in the Dockerfile does not match the file in the build context.

Check:

```bash
ls -lah
```

### Application image builds but fails at runtime

Separate image-build success from application-runtime success. Inspect:

```bash
docker logs <container-name>
```

Then validate database, Kafka, filesystem mounts, TLS material, environment-variable mapping, and network reachability independently.
