# Kafka KRaft: Safe Port Migration

Changing a normal client listener can often be rolled gradually. Changing the KRaft controller port is different because every voter must agree on the controller quorum endpoints.

## Example migration

```text
Old client listener      -> new client listener
Old controller listener  -> new controller listener

PLAINTEXT     -> 18092
SASLCLIENT    -> 18094
CONTROLLER    -> 18275
```

## 1. Confirm topology

On every node:

```bash
grep -nE '^(process.roles|node.id|controller.quorum.voters|listeners|advertised.listeners|listener.security.protocol.map|inter.broker.listener.name|controller.listener.names)' /opt/kafka/config/kraft/server.properties
```

Verify node IDs and advertised addresses before editing.

## 2. Back up configuration

```bash
cp -a /opt/kafka/config/kraft/server.properties \
  /opt/kafka/config/kraft/server.properties.bak-$(date +%Y%m%d-%H%M%S)
```

## 3. Verify target ports are free

```bash
ss -lntp | grep -E ':(18092|18094|18275)\b' || echo "Target Kafka ports are free"
```

## 4. Update all three configs before restart

Every node must receive the same voter list:

```properties
controller.quorum.voters=1@<NODE_1_IP>:18275,2@<NODE_2_IP>:18275,3@<NODE_3_IP>:18275
```

Each node advertises its own address:

```properties
advertised.listeners=PLAINTEXT://<THIS_NODE_IP>:18092,SASLCLIENT://<THIS_NODE_IP>:18094
```

## 5. Coordinated restart

When the controller port changes, plan a maintenance window.

Stop Kafka on all quorum members:

```bash
systemctl stop kafka
```

After every node has the new configuration, start the nodes:

```bash
systemctl start kafka
```

## 6. Validate listeners

```bash
systemctl is-active kafka
ss -lntp | grep -E ':(18092|18094|18275)\b'
```

## 7. Validate KRaft

```bash
/opt/kafka/bin/kafka-metadata-quorum.sh \
  --bootstrap-server 127.0.0.1:18092 \
  describe --status
```

Healthy indicators include:

```text
MaxFollowerLag: 0
CurrentVoters: [1,2,3]
```

## 8. Validate topics

```bash
/opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server 127.0.0.1:18092 \
  --list
```

## 9. Confirm old ports are gone

```bash
ss -lntp | grep -E ':(<OLD_PORT_1>|<OLD_PORT_2>|<OLD_PORT_3>)\b' || \
  echo "Old Kafka ports are no longer listening"
```

Changing a port number is not a security control by itself. Security comes from authentication, authorization, TLS where required, and network restrictions/firewall rules.
