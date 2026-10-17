# Kafka KRaft: Rolling mTLS Listener Rollout

I used a rolling change to add an application mTLS listener to a three-node KRaft cluster without removing the old listener first. The difficult part was not just enabling SSL on brokers: the Java client properties, PKCS12/JKS files, certificate identities and consumer behavior all had to agree. This is the procedure and verification checklist from that work, with addresses and secrets removed.

> All addresses, ports, credentials, certificate material, cluster identifiers, and organization-specific names must remain environment-specific and must not be committed to source control.

## Goal

Add a new application-facing SSL listener with mandatory client certificates without changing the inter-broker listener or controller listener during the migration window.

Example listener model:

```properties
listeners=PLAINTEXT://0.0.0.0:<internal-port>,EXTERNAL://0.0.0.0:<legacy-port>,MTLS://0.0.0.0:<mtls-port>,CONTROLLER://0.0.0.0:<controller-port>
advertised.listeners=PLAINTEXT://<broker-ip>:<internal-port>,EXTERNAL://<broker-ip>:<legacy-port>,MTLS://<broker-ip>:<mtls-port>
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,EXTERNAL:PLAINTEXT,MTLS:SSL,CONTROLLER:PLAINTEXT
```

TLS settings:

```properties
ssl.keystore.location=/etc/kafka/ssl/broker.p12
ssl.keystore.password=<secret>
ssl.key.password=<secret>
ssl.keystore.type=PKCS12
ssl.truststore.location=/etc/kafka/ssl/truststore.p12
ssl.truststore.password=<secret>
ssl.truststore.type=PKCS12
listener.name.mtls.ssl.client.auth=required
ssl.enabled.protocols=TLSv1.2,TLSv1.3
```

## 1. Preflight the KRaft quorum

Before changing any broker, validate the metadata quorum from a healthy node:

```bash
kafka-metadata-quorum.sh --bootstrap-server <healthy-broker>:<internal-port> describe --status
```

Confirm:

- every expected voter is present
- follower lag is healthy
- the cluster ID is the expected cluster
- no unrelated controller instability is already present

Do not begin a rolling restart while the quorum is degraded.

## 2. Roll non-leader brokers first

For a three-node cluster, change one non-leader at a time.

Recommended sequence:

1. non-leader broker A
2. validate quorum and listener health
3. non-leader broker B
4. validate again
5. current controller leader last

The exact node numbers do not matter. The safety property is that only one broker is restarted at a time and the current leader is left until last when practical.

## 3. Back up before changing configuration

```bash
cp -a /path/to/server.properties \
  /path/to/server.properties.pre-mtls-$(date +%Y%m%d-%H%M%S)
```

Prefer a scripted or atomic update rather than interactive editing on a production broker. Validate the broker identity (`node.id` and advertised address) before writing the file so configuration intended for one node cannot silently be applied to another.

## 4. Validate certificate stores before restart

```bash
keytool -list -storetype PKCS12 -keystore /etc/kafka/ssl/broker.p12
keytool -list -storetype PKCS12 -keystore /etc/kafka/ssl/truststore.p12
```

Expected:

- broker keystore opens successfully and contains a private key entry
- truststore opens successfully and contains the expected CA
- broker certificate SAN includes the hostname/IP clients will verify

Do not restart Kafka if the stores cannot be opened with the configured passwords.

## 5. Restart only the target broker

```bash
systemctl restart kafka
sleep 8
systemctl --no-pager --full status kafka
```

Validate all expected listeners:

```bash
ss -lntp | grep -E ':(<internal-port>|<legacy-port>|<mtls-port>|<controller-port>)\b'
```

Check startup errors:

```bash
journalctl -u kafka --since '3 minutes ago' --no-pager | \
  grep -Ei 'ERROR|FATAL|exception|keystore|truststore|SSL|bind|failed'
```

## 6. Recheck quorum after every broker

```bash
kafka-metadata-quorum.sh --bootstrap-server <healthy-broker>:<internal-port> describe --status
```

Healthy output should still show all voters and acceptable follower lag.

If a non-leader restart causes quorum degradation, stop the rollout and repair the cluster before touching another broker.

## 7. Validate mTLS from an application host

TCP reachability is only a first check:

```bash
timeout 3 bash -c '</dev/tcp/<broker>/<mtls-port>'
```

Then perform a real TLS handshake with the application client certificate and CA:

```bash
openssl s_client \
  -connect <broker>:<mtls-port> \
  -cert client.crt \
  -key client.key \
  -CAfile ca.crt \
  -verify_return_error \
  -verify_ip <broker-ip> \
  -brief
```

Expected:

```text
CONNECTION ESTABLISHED
Verification: OK
```

A successful `s_client` connection supports TLS trust and the presented certificate path, but it does not by itself prove Kafka authorization, successful produce/consume, or even that the broker required a client certificate. Test a client *without* a certificate as a separate negative case. Use `-verify_hostname <broker-dns>` when connecting by DNS, or `-verify_ip <broker-ip>` when verifying an IP SAN.

## 8. Distinguish broker TLS health from application configuration

A common failure pattern is:

- direct `openssl s_client` mTLS succeeds
- the application still disconnects during Kafka negotiation
- broker logs show `SSL handshake failed`

When this happens, inspect the application's effective runtime Kafka configuration before changing the broker again.

For Java clients, verify at runtime:

```text
security.protocol = SSL
ssl.keystore.location = ...
ssl.keystore.type = PKCS12
ssl.truststore.location = ...
ssl.truststore.type = PKCS12
ssl.endpoint.identification.algorithm = https
```

A duplicate Java property such as:

```properties
kafka.security.protocol=SSL
kafka.security.protocol=PLAINTEXT
```

can make the later `PLAINTEXT` value effective and cause the application to send cleartext Kafka protocol to an SSL listener. The resulting broker-side symptom can look like a certificate problem even when the certificates are valid.

## 9. Rebuild a PKCS12 container without reissuing the certificate

If the certificate and private key still exist and match, but the PKCS12 password is unknown, verify that they belong together first. The modulus check below works for RSA keys; for EC or other keys, compare the public-key fingerprints instead:

```bash
openssl x509 -noout -modulus -in client.crt | openssl sha256
openssl rsa  -noout -modulus -in client.key | openssl sha256
```

If the hashes match, rebuild only the container:

```bash
openssl pkcs12 -export \
  -name <client-alias> \
  -inkey client.key \
  -in client.crt \
  -certfile ca.crt \
  -out client.new.p12
```

This preserves the existing certificate identity and avoids unnecessary reissuance.

Be careful to copy the newly created file, not the old container with a similar filename. Compare SHA-256 checksums before installing it on the application host.

## 10. Handle log timestamp differences

Application and broker hosts may log in different time zones or use different timestamp conventions. During validation, establish the offset before deciding whether a broker handshake failure happened before or after an application redeploy.

A clean post-change boundary is more useful than a broad `--since '10 minutes ago'` query.

Example:

```bash
journalctl -u kafka --since '<known-post-fix-time>' --no-pager | \
  grep -c 'Failed authentication with /<application-ip>'
```

Expected after a successful fix:

```text
0
```

## 11. Restart the controller leader last

After both non-leaders are healthy, restart the current KRaft leader last.

Leadership may move to another voter. That is normal.

Final quorum validation should focus on:

- all voters present
- `MaxFollowerLag` healthy, ideally zero after convergence
- no unexpected observers
- stable cluster ID

The leader does not need to return to its original node.

## 12. Final completion criteria

The broker-side rollout is complete only when:

- every broker exposes the new mTLS listener
- all original migration listeners remain available as required
- each broker certificate passes SAN verification
- client-certificate authentication succeeds to every broker
- a connection without a valid client certificate is rejected
- KRaft contains all expected voters
- follower lag converges to a healthy value
- the application loads `security.protocol=SSL`
- the application receives Kafka metadata from the expected cluster
- no new broker-side TLS authentication failures appear after the final application redeploy

Only after this should legacy-listener retirement be planned as a separate change.