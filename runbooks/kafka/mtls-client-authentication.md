# Kafka: mTLS client authentication with PKCS12

This runbook shows how to add a dedicated Kafka client listener that uses **mutual TLS (mTLS)**. The broker presents a server certificate and also requires the client application to present a trusted client certificate.

The examples are intentionally generic. Replace all hostnames, IPs, paths, and passwords for your environment.

## Target listener model

| Purpose | Example port | Security |
|---|---:|---|
| Inter-broker / temporary admin | `18092` | PLAINTEXT, network restricted |
| Existing migration listener | `18094` | SASL_PLAINTEXT + SCRAM-SHA-512 |
| Application clients | `18443` | SSL + required client certificate |
| KRaft controller | `18275` | Controller traffic only |

The application listener uses `security.protocol=SSL`. It does **not** use SCRAM credentials. The client certificate is the authentication credential.

## 1. Build a private CA

Keep the CA private key only on a secured administration host.

```bash
mkdir -p /root/kafka-pki/ca
cd /root/kafka-pki/ca

openssl genrsa -out kafka-ca.key 4096
openssl req -x509 -new -sha256 \
  -key kafka-ca.key \
  -days 3650 \
  -out kafka-ca.crt \
  -subj "/C=XX/O=Example Infrastructure/OU=Kafka/CN=Kafka Internal Root CA"

chmod 600 kafka-ca.key
```

## 2. Create one certificate per broker

Each broker certificate must contain the exact DNS name and/or IP address clients use to connect.

Example broker CSR configuration:

```ini
[req]
prompt = no
distinguished_name = dn
req_extensions = req_ext

[dn]
C = XX
O = Example Infrastructure
OU = Kafka
CN = kafka-broker-01

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = kafka-broker-01
IP.1 = 10.10.20.11
```

Generate the key and CSR on the broker so the private key never leaves that host:

```bash
openssl genrsa -out /etc/kafka/ssl/broker.key 3072
openssl req -new -sha256 \
  -key /etc/kafka/ssl/broker.key \
  -out /etc/kafka/ssl/broker.csr \
  -config /etc/kafka/ssl/broker-openssl.cnf
```

Sign the CSR on the CA host with extensions such as:

```ini
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:kafka-broker-01,IP:10.10.20.11
```

Then verify:

```bash
openssl verify -CAfile kafka-ca.crt broker.crt
openssl x509 -in broker.crt -noout -subject -issuer -dates -ext subjectAltName
```

## 3. Create broker PKCS12 stores

```bash
openssl pkcs12 -export \
  -name kafka-broker \
  -inkey broker.key \
  -in broker.crt \
  -certfile ca.crt \
  -out broker.p12 \
  -passout pass:'<BROKER_STORE_PASSWORD>'

keytool -importcert -noprompt \
  -alias kafka-internal-ca \
  -file ca.crt \
  -keystore truststore.p12 \
  -storetype PKCS12 \
  -storepass '<BROKER_STORE_PASSWORD>'
```

Suggested permissions:

```bash
chown root:kafka /etc/kafka/ssl/{broker.key,broker.p12,truststore.p12}
chmod 640 /etc/kafka/ssl/{broker.key,broker.p12,truststore.p12}
chmod 644 /etc/kafka/ssl/{broker.crt,ca.crt}
```

## 4. Configure the broker mTLS listener

Example `server.properties` entries:

```properties
listeners=PLAINTEXT://0.0.0.0:18092,SASLCLIENT://0.0.0.0:18094,MTLS://0.0.0.0:18443,CONTROLLER://0.0.0.0:18275
advertised.listeners=PLAINTEXT://10.10.20.11:18092,SASLCLIENT://10.10.20.11:18094,MTLS://10.10.20.11:18443
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SASLCLIENT:SASL_PLAINTEXT,MTLS:SSL
inter.broker.listener.name=PLAINTEXT
controller.listener.names=CONTROLLER

ssl.keystore.location=/etc/kafka/ssl/broker.p12
ssl.keystore.password=<BROKER_STORE_PASSWORD>
ssl.key.password=<BROKER_STORE_PASSWORD>
ssl.keystore.type=PKCS12

ssl.truststore.location=/etc/kafka/ssl/truststore.p12
ssl.truststore.password=<BROKER_STORE_PASSWORD>
ssl.truststore.type=PKCS12

ssl.client.auth=required
ssl.enabled.protocols=TLSv1.2,TLSv1.3
```

Back up the configuration before editing and restart one broker at a time in a three-node cluster.

After each restart:

```bash
systemctl is-active kafka
ss -lntp | grep -E ':(18092|18094|18275|18443)\b'
```

Validate KRaft health:

```bash
/opt/kafka/bin/kafka-metadata-quorum.sh \
  --bootstrap-server 127.0.0.1:18092 \
  describe --status
```

Do not continue a rolling restart if quorum health is degraded.

## 5. Create an application client certificate

Use a distinct client identity for each application or trust boundary.

```bash
openssl genrsa -out app-client.key 3072

openssl req -new -sha256 \
  -key app-client.key \
  -out app-client.csr \
  -subj "/C=XX/O=Example Infrastructure/OU=Kafka Clients/CN=app-client"
```

Client certificate extension file:

```ini
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
```

Sign it with the Kafka CA, then verify:

```bash
openssl verify -CAfile kafka-ca.crt app-client.crt
openssl x509 -in app-client.crt -noout -subject -issuer -text | grep -A3 'Extended Key Usage'
```

The certificate should include `TLS Web Client Authentication`.

Create the client keystore and truststore:

```bash
openssl pkcs12 -export \
  -name app-client \
  -inkey app-client.key \
  -in app-client.crt \
  -certfile kafka-ca.crt \
  -out app-client.p12 \
  -passout pass:'<CLIENT_KEYSTORE_PASSWORD>'

keytool -importcert -noprompt \
  -alias kafka-ca \
  -file kafka-ca.crt \
  -keystore app-client-truststore.p12 \
  -storetype PKCS12 \
  -storepass '<CLIENT_TRUSTSTORE_PASSWORD>'
```

Only distribute the PKCS12 files required by the application. Do not distribute the CA private key.

## 6. Kafka client configuration

```properties
security.protocol=SSL
ssl.truststore.location=/etc/ssl/kafka/app-client-truststore.p12
ssl.truststore.password=<CLIENT_TRUSTSTORE_PASSWORD>
ssl.truststore.type=PKCS12

ssl.keystore.location=/etc/ssl/kafka/app-client.p12
ssl.keystore.password=<CLIENT_KEYSTORE_PASSWORD>
ssl.keystore.type=PKCS12
ssl.key.password=<CLIENT_KEYSTORE_PASSWORD>

ssl.endpoint.identification.algorithm=https
```

Keep hostname verification enabled. Broker certificates should be fixed instead of disabling endpoint identification.

## 7. Positive and negative validation

A successful mTLS rollout should prove both acceptance and rejection behavior.

Valid client certificate:

```bash
kafka-topics.sh \
  --bootstrap-server 10.10.20.11:18443 \
  --command-config /tmp/kafka-mtls.properties \
  --list
```

Expected: the topic list is returned.

Trust the broker CA but omit the client keystore:

```bash
kafka-topics.sh \
  --bootstrap-server 10.10.20.11:18443 \
  --command-config /tmp/kafka-ssl-no-client-cert.properties \
  --list
```

Expected: TLS authentication fails, commonly with `bad_certificate` or an SSL handshake error.

Certificate-level verification:

```bash
openssl s_client \
  -connect 10.10.20.11:18443 \
  -servername kafka-broker-01 \
  -cert app-client.crt \
  -key app-client.key \
  -CAfile kafka-ca.crt \
  -verify_return_error \
  -verify_hostname kafka-broker-01 \
  </dev/null
```

Expected:

```text
Verification: OK
Verify return code: 0 (ok)
```

## 8. Application deployment pattern

A Java application can consume environment variables such as:

```bash
export APP_KAFKA_URL="10.10.20.11:18443,10.10.20.12:18443,10.10.20.13:18443"
export APP_KAFKA_TRUSTSTORE_LOCATION="file:/etc/ssl/kafka/app-client-truststore.p12"
export APP_KAFKA_TRUSTSTORE_PASSWORD="<CLIENT_TRUSTSTORE_PASSWORD>"
export APP_KAFKA_TRUSTSTORE_TYPE="PKCS12"
export APP_KAFKA_KEYSTORE_LOCATION="file:/etc/ssl/kafka/app-client.p12"
export APP_KAFKA_KEYSTORE_PASSWORD="<CLIENT_KEYSTORE_PASSWORD>"
export APP_KAFKA_KEYSTORE_TYPE="PKCS12"
export APP_KAFKA_KEY_PASSWORD="<CLIENT_KEYSTORE_PASSWORD>"
export APP_KAFKA_HOSTNAME_VERIFICATION="https"
```

Whether the application also needs an explicit `security.protocol=SSL` environment variable depends on how its configuration code is implemented.

## 9. Production hardening

- Use application-specific client certificates rather than one shared client identity.
- Protect broker and client keystore passwords with the platform's secret-management mechanism.
- Restrict controller and internal listener ports with firewall rules.
- Keep the CA private key offline or tightly access-controlled.
- Rotate certificates and store passwords according to organizational policy.
- Keep hostname verification enabled.
- Add Kafka ACL authorization if clients need topic-level restrictions; mTLS authenticates the certificate identity but does not by itself enforce topic permissions.
- Never commit `.key`, `.p12`, `.jks`, passwords, internal IPs, or real certificate material to a public repository.
