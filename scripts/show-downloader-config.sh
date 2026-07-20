#!/usr/bin/env bash
set -euo pipefail

environment_file="${HARMONY_ENV_FILE:-/etc/harmony-platform/harmony-platform.env}"
certificate_file=/etc/harmony-platform/rabbitmq-certs/tls.crt

test "$(id -u)" -eq 0
test -r "$environment_file"
test -r "$certificate_file"

set -a
# shellcheck disable=SC1090
source "$environment_file"
set +a

: "${DOWNLOADER_RABBITMQ_PASSWORD:?DOWNLOADER_RABBITMQ_PASSWORD is required}"
fingerprint="$(
  openssl x509 -in "$certificate_file" -noout -fingerprint -sha256 \
    | sed 's/^[^=]*=//' \
    | tr -d ':'
)"

printf 'RABBITMQ_URI=amqps://downloader:%s@harmony-resolver.duckdns.org:5671/\n' \
  "$DOWNLOADER_RABBITMQ_PASSWORD"
printf 'RABBITMQ_CERT_SHA256=%s\n' "$fingerprint"
