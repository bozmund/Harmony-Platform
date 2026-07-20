#!/usr/bin/env bash
set -euo pipefail

platform_directory=/opt/harmony-platform
configuration_directory=/etc/harmony-platform
environment_file="$configuration_directory/harmony-platform.env"
legacy_environment_file=/etc/harmony-resolver/harmony-resolver.env
certificate_directory="$configuration_directory/rabbitmq-certs"
downloader_host=harmony-resolver.duckdns.org

test "$(id -u)" -eq 0
install -d -m 755 "$configuration_directory" /var/backups/harmony-platform
install -d -m 700 -o 999 -g 999 "$certificate_directory"

if [ ! -e "$environment_file" ]; then
  umask 077
  if [ -r "$legacy_environment_file" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$legacy_environment_file"
    set +a
  fi
  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 32)}"
  MINIO_ROOT_USER="${MINIO_ROOT_USER:-harmony}"
  MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-$(openssl rand -hex 32)}"
  RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(openssl rand -hex 32)}"
  IDENTITY_HMAC_KEY="${IDENTITY_HMAC_KEY:-$(openssl rand -hex 32)}"
  cat >"$environment_file" <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
MINIO_ROOT_USER=$MINIO_ROOT_USER
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD
RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD
IDENTITY_HMAC_KEY=$IDENTITY_HMAC_KEY
CLOUD_IDENTITY_HMAC_KEY=$(openssl rand -hex 32)
AUTH0_DOMAIN=
CLOUD_AUTH0_CLIENT_ID=
CLOUD_AUTH0_CLIENT_SECRET=
GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 24)
DUCKDNS_TOKEN=
EOF
fi

if [ ! -s "$certificate_directory/tls.crt" ] || [ ! -s "$certificate_directory/tls.key" ]; then
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
    -subj "/CN=$downloader_host" \
    -addext "subjectAltName=DNS:$downloader_host" \
    -keyout "$certificate_directory/tls.key" \
    -out "$certificate_directory/tls.crt"
  chown 999:999 "$certificate_directory/tls.crt" "$certificate_directory/tls.key"
  chmod 644 "$certificate_directory/tls.crt"
  chmod 600 "$certificate_directory/tls.key"
fi
install -m 644 -o 999 -g 999 \
  "$certificate_directory/tls.crt" "$certificate_directory/ca.crt"

deploy_user=deploy
id "$deploy_user" >/dev/null
chown -R "$deploy_user:$deploy_user" "$platform_directory"
cat >/etc/sudoers.d/harmony-platform-deploy <<EOF
$deploy_user ALL=(root) NOPASSWD: /usr/bin/bash $platform_directory/scripts/deploy.sh
EOF
chmod 440 /etc/sudoers.d/harmony-platform-deploy
visudo -cf /etc/sudoers.d/harmony-platform-deploy

openssl x509 -in "$certificate_directory/tls.crt" -noout -fingerprint -sha256
echo "Edit $environment_file once, then GitHub Actions owns deployments."
