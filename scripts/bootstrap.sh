#!/usr/bin/env bash
set -euo pipefail

platform_directory=/opt/harmony-platform
configuration_directory=/etc/harmony-platform
environment_file="$configuration_directory/harmony-platform.env"
legacy_environment_file=/etc/harmony-resolver/harmony-resolver.env
certificate_directory="$configuration_directory/rabbitmq-certs"
downloader_host=harmony-resolver.duckdns.org
requested_auth0_domain="${AUTH0_DOMAIN:-}"
requested_cloud_client_id="${CLOUD_AUTH0_CLIENT_ID:-}"
requested_cloud_client_secret="${CLOUD_AUTH0_CLIENT_SECRET:-}"
requested_deploy_key_b64="${DEPLOY_AUTHORIZED_KEY_B64:-}"

test "$(id -u)" -eq 0

apt-get update
apt-get install -y ca-certificates curl git gnupg openssl
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q 'Status: active'; then
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 5671/tcp
else
  for port in 80 443 5671; do
    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null \
      || iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
  done
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
  fi
fi

deploy_user=deploy
if ! id "$deploy_user" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$deploy_user"
fi
if [ -n "$requested_deploy_key_b64" ]; then
  deploy_ssh_directory="/home/$deploy_user/.ssh"
  install -d -m 700 -o "$deploy_user" -g "$deploy_user" "$deploy_ssh_directory"
  printf '%s' "$requested_deploy_key_b64" \
    | base64 --decode >"$deploy_ssh_directory/authorized_keys"
  grep -Eq '^ssh-(ed25519|rsa) ' "$deploy_ssh_directory/authorized_keys"
  chown "$deploy_user:$deploy_user" "$deploy_ssh_directory/authorized_keys"
  chmod 600 "$deploy_ssh_directory/authorized_keys"
fi

install -d -m 755 "$configuration_directory" /var/backups/harmony-platform
rabbitmq_uid="$(docker run --rm --entrypoint id rabbitmq:4-management-alpine -u rabbitmq)"
rabbitmq_gid="$(docker run --rm --entrypoint id rabbitmq:4-management-alpine -g rabbitmq)"
install -d -m 700 -o "$rabbitmq_uid" -g "$rabbitmq_gid" "$certificate_directory"

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
  DOWNLOADER_RABBITMQ_PASSWORD="$(openssl rand -hex 32)"
  IDENTITY_HMAC_KEY="${IDENTITY_HMAC_KEY:-$(openssl rand -hex 32)}"
  cat >"$environment_file" <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
MINIO_ROOT_USER=$MINIO_ROOT_USER
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD
RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD
DOWNLOADER_RABBITMQ_PASSWORD=$DOWNLOADER_RABBITMQ_PASSWORD
IDENTITY_HMAC_KEY=$IDENTITY_HMAC_KEY
CLOUD_IDENTITY_HMAC_KEY=$(openssl rand -hex 32)
AUTH0_DOMAIN=$requested_auth0_domain
CLOUD_AUTH0_CLIENT_ID=$requested_cloud_client_id
CLOUD_AUTH0_CLIENT_SECRET=$requested_cloud_client_secret
GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 24)
DUCKDNS_TOKEN=
EOF
fi

set_environment_value() {
  local key="$1"
  local value="$2"
  local temporary_file
  temporary_file="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    index($0, key "=") == 1 {
      print key "=" value
      found = 1
      next
    }
    { print }
    END {
      if (!found) {
        print key "=" value
      }
    }
  ' "$environment_file" >"$temporary_file"
  install -m 600 -o root -g root "$temporary_file" "$environment_file"
  rm -f "$temporary_file"
}

if [ -n "$requested_auth0_domain" ]; then
  set_environment_value AUTH0_DOMAIN "$requested_auth0_domain"
fi
if [ -n "$requested_cloud_client_id" ]; then
  set_environment_value CLOUD_AUTH0_CLIENT_ID "$requested_cloud_client_id"
fi
if [ -n "$requested_cloud_client_secret" ]; then
  set_environment_value CLOUD_AUTH0_CLIENT_SECRET "$requested_cloud_client_secret"
fi

if ! grep -q '^DOWNLOADER_RABBITMQ_PASSWORD=' "$environment_file"; then
  printf 'DOWNLOADER_RABBITMQ_PASSWORD=%s\n' "$(openssl rand -hex 32)" >>"$environment_file"
fi
chown root:root "$environment_file"
chmod 600 "$environment_file"

if [ ! -s "$certificate_directory/tls.crt" ] || [ ! -s "$certificate_directory/tls.key" ]; then
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
    -subj "/CN=$downloader_host" \
    -addext "subjectAltName=DNS:$downloader_host" \
    -keyout "$certificate_directory/tls.key" \
    -out "$certificate_directory/tls.crt"
  chown "$rabbitmq_uid:$rabbitmq_gid" "$certificate_directory/tls.crt" "$certificate_directory/tls.key"
  chmod 644 "$certificate_directory/tls.crt"
  chmod 600 "$certificate_directory/tls.key"
fi
install -m 644 -o "$rabbitmq_uid" -g "$rabbitmq_gid" \
  "$certificate_directory/tls.crt" "$certificate_directory/ca.crt"

chown -R root:root "$platform_directory"
install -m 755 -o root -g root \
  "$platform_directory/scripts/deploy-wrapper.sh" \
  /usr/local/sbin/harmony-platform-deploy
cat >/etc/sudoers.d/harmony-platform-deploy <<EOF
$deploy_user ALL=(root) NOPASSWD: /usr/local/sbin/harmony-platform-deploy *
EOF
chmod 440 /etc/sudoers.d/harmony-platform-deploy
visudo -cf /etc/sudoers.d/harmony-platform-deploy

openssl x509 -in "$certificate_directory/tls.crt" -noout -fingerprint -sha256
if grep -Eq '^(AUTH0_DOMAIN|CLOUD_AUTH0_CLIENT_ID|CLOUD_AUTH0_CLIENT_SECRET)=$' "$environment_file"; then
  echo "Auth0 settings are incomplete in $environment_file." >&2
  echo "Provide them to the bootstrap workflow or edit the file once before deployment." >&2
else
  echo "Runtime secrets are ready; GitHub Actions now owns deployments."
fi
echo "After the first successful deploy, run scripts/show-downloader-config.sh as root."
