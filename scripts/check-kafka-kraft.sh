#!/usr/bin/env bash
set -Eeuo pipefail

KAFKA_HOME="${KAFKA_HOME:-/opt/kafka}"
BOOTSTRAP="${BOOTSTRAP:-127.0.0.1:18092}"

printf '=== Kafka service ===\n'
systemctl is-active kafka || true

printf '\n=== Kafka listeners ===\n'
ss -lntp | grep -E ':(18092|18094|18275)\b' || true

printf '\n=== KRaft quorum ===\n'
"$KAFKA_HOME/bin/kafka-metadata-quorum.sh" --bootstrap-server "$BOOTSTRAP" describe --status

printf '\n=== Topics ===\n'
"$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP" --list
