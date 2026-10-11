# WildFly Kafka Client Migration to mTLS

This runbook covers migrating an existing WildFly-hosted Kafka producer from a legacy Kafka endpoint to a Kafka listener that requires mutual TLS (mTLS).

> Replace all hostnames, ports, paths, topic names, and passwords with values from the target environment. Never commit real credentials, keystores, truststores, private keys, internal IPs, or certificate fingerprints.

## Scenario

An existing WAR already produces Kafka messages successfully. The Kafka platform has been upgraded with a dedicated SSL listener configured with `ssl.client.auth=required`. The application must be migrated without changing unrelated WildFly deployments.

## 1. Identify the correct WildFly instance

Multiple WildFly installations may exist on the same host.

```bash
ps -eo user,pid,cmd | grep -Ei 'wildfly|jboss|java' | grep -v grep
ss -lntp | grep -E ':(8080|9990|9995)\b'
```

Confirm the management port and installation path before changing anything.

```bash
/opt/wildfly/bin/jboss-cli.sh --connect --controller=127.0.0.1:<management-port> --commands='deployment-info'
```

## 2. Confirm the existing application really uses Kafka

```bash
grep -Ei 'ProducerConfig values:|Producer clientId=|Cluster ID:|MESSAGE SENT TO KAFKA|KafkaProducer' \
  /opt/wildfly/standalone/log/server.log | tail -300
```

This avoids migrating the wrong deployment.

## 3. Install the client certificate stores

Recommended layout:

```text
/etc/ssl/kafka/
├── service-client.p12
└── service-client-truststore.p12
```

```bash
mkdir -p /etc/ssl/kafka
chown root:root /etc/ssl/kafka/*.p12
chmod 600 /etc/ssl/kafka/*.p12
```

If a checksum file is supplied:

```bash
cd /etc/ssl/kafka
sha256sum -c SHA256SUMS
```

Verify the client keystore:

```bash
keytool -list -keystore /etc/ssl/kafka/service-client.p12 -storetype PKCS12
```

Expected: at least one `PrivateKeyEntry`.

Verify the truststore:

```bash
keytool -list -keystore /etc/ssl/kafka/service-client-truststore.p12 -storetype PKCS12
```

Expected: the Kafka CA as a `trustedCertEntry`.

## 4. Verify network reachability to every broker

```bash
for HOST in broker-1.example broker-2.example broker-3.example; do
  echo "=== $HOST ==="
  timeout 3 bash -c "</dev/tcp/$HOST/<ssl-port>" && echo OK || echo FAILED
done
```

TCP reachability is not an mTLS proof, but it eliminates routing and firewall issues first.

## 5. Update the application Kafka properties

Example:

```properties
kafka.bootstrap.servers=broker-1.example:18443,broker-2.example:18443,broker-3.example:18443
kafka.topicName=failed-transaction-alerts
kafka.security.protocol=SSL
kafka.ssl.truststore.location=/etc/ssl/kafka/service-client-truststore.p12
kafka.ssl.truststore.password=<secret>
kafka.ssl.truststore.type=PKCS12
kafka.ssl.keystore.location=/etc/ssl/kafka/service-client.p12
kafka.ssl.keystore.password=<secret>
kafka.ssl.keystore.type=PKCS12
kafka.ssl.key.password=<secret>
kafka.ssl.endpoint.identification.algorithm=https
```

Important checks:

- Do not define `kafka.security.protocol` twice.
- Remove any legacy `PLAINTEXT` value when testing mTLS.
- In ordinary Java `.properties` loading, a later duplicate key can override the earlier value. A file containing both `SSL` and then `PLAINTEXT` can therefore make the effective protocol `PLAINTEXT` even though the intended SSL line is present.
- Do not append shell-style trailing `\` characters to Java `.properties` lines.
- Keep hostname verification enabled when broker certificates have correct SANs.

## 6. Redeploy only the target WAR

Prefer redeploying the affected deployment rather than restarting every application on the server.

Use the environment's normal deployment process. Do not manually edit files under WildFly's `standalone/tmp/vfs` or `standalone/data/content` directories.

Replacing a PKCS12 file on disk is not enough if the Kafka producer has already initialized. Redeploy or restart the affected application so the Kafka client rebuilds its SSL context and reloads the certificate stores.

## 7. Verify the application loaded the new settings

```bash
grep -A80 -B5 'ProducerConfig values:' /opt/wildfly/standalone/log/server.log | tail -120
```

Expected values include:

```text
bootstrap.servers = [broker-1.example:18443, ...]
security.protocol = SSL
ssl.keystore.location = /etc/ssl/kafka/service-client.p12
ssl.truststore.location = /etc/ssl/kafka/service-client-truststore.p12
ssl.endpoint.identification.algorithm = https
```

A successful metadata connection normally also shows a Kafka cluster ID:

```text
[Producer clientId=<client-id>] Cluster ID: <cluster-id>
```

## 8. Prove TLS independently of the WAR

If the broker reports `SSL handshake failed`, test the exact client identity independently of WildFly.

Extract temporary PEM material from the PKCS12 stores:

```bash
mkdir -m 700 /tmp/kafka-mtls-test
openssl pkcs12 -in /etc/ssl/kafka/service-client.p12 -clcerts -nokeys -out /tmp/kafka-mtls-test/client.crt
openssl pkcs12 -in /etc/ssl/kafka/service-client.p12 -nocerts -nodes -out /tmp/kafka-mtls-test/client.key
chmod 600 /tmp/kafka-mtls-test/client.key
openssl pkcs12 -in /etc/ssl/kafka/service-client-truststore.p12 -nokeys -out /tmp/kafka-mtls-test/ca.crt
```

Then test the broker:

```bash
openssl s_client \
  -connect <broker>:<ssl-port> \
  -cert /tmp/kafka-mtls-test/client.crt \
  -key /tmp/kafka-mtls-test/client.key \
  -CAfile /tmp/kafka-mtls-test/ca.crt \
  -verify_return_error \
  -verify_ip <broker-ip> \
  -brief
```

If this returns `Verification: OK` but the Java producer still fails, the broker certificate, client identity, and trust relationship are already proven. Inspect the application's effective runtime settings before changing Kafka again.

Always remove temporary extracted private-key material after testing:

```bash
rm -rf /tmp/kafka-mtls-test
```

## 9. Complete end-to-end validation

Trigger the application's real Kafka publish path and monitor:

```bash
tail -F /opt/wildfly/standalone/log/server.log | \
  grep --line-buffered -Ei 'org\.apache\.kafka|Producer clientId=|Cluster ID:|MESSAGE SENT TO KAFKA|SSLHandshakeException|KafkaException'
```

The strongest application-level success signal is a line showing a successful send with topic, partition, and offset.

When correlating application and broker logs, confirm whether both hosts use the same timezone. A fixed offset can make pre-redeploy broker failures appear newer than the successful application startup if timestamps are compared without normalization.

## Common failures

### `SSLHandshakeException`

Check:

- client cert signed by a CA trusted by the broker
- broker cert signed by a CA trusted by the client
- keystore contains a private key
- listener requires the expected client authentication mode

### `PKIX path building failed`

The truststore does not trust the broker certificate chain.

### `bad_certificate`

The broker rejected the client certificate or no usable client certificate was presented.

### Direct OpenSSL succeeds but the WAR still fails

Inspect the Kafka producer's effective configuration. In particular, search for duplicate `kafka.security.protocol` values and verify the deployed producer actually logs `security.protocol = SSL`.

### PKCS12 password is unknown but the original key and certificate still exist

Do not brute-force the store. Verify that the private key matches the certificate:

```bash
openssl x509 -noout -modulus -in client.crt | openssl sha256
openssl rsa  -noout -modulus -in client.key | openssl sha256
```

If the hashes match, rebuild only the PKCS12 container with a new known password. Reissuing the certificate is unnecessary.

After rebuilding, compare checksums before copying to the application host. Be careful not to copy the old file when the new file has a similar `.new.p12` name.

### Hostname verification failure

Fix the broker certificate SAN. Do not disable hostname verification as the default workaround.

### Application still connects to the old endpoint

Confirm the deployed WAR actually contains or loads the new configuration. Do not inspect only source files on disk; inspect runtime `ProducerConfig` values after deployment.

## Completion criteria

- client keystore checksum verified
- truststore checksum verified
- keystore contains `PrivateKeyEntry`
- truststore contains Kafka CA
- all brokers reachable on SSL listener
- direct mTLS handshake succeeds with endpoint verification
- runtime producer shows `security.protocol = SSL`
- runtime producer shows correct keystore/truststore paths
- runtime producer connects to expected Kafka cluster
- no new broker-side TLS authentication failures after the successful redeploy boundary
- real application publish succeeds
