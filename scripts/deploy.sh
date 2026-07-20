#!/usr/bin/env bash
set -euo pipefail

workspace="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment_file="${HARMONY_ENV_FILE:-/etc/harmony-platform/harmony-platform.env}"
backup_directory="${HARMONY_BACKUP_DIR:-/var/backups/harmony-platform}"

test -r "$environment_file"
mkdir -p "$backup_directory"

cd "$workspace"
set -a
# shellcheck disable=SC1090
source "$environment_file"
set +a

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
if systemctl is-active --quiet harmony-resolver.service; then
  legacy_environment=/etc/harmony-resolver/harmony-resolver.env
  legacy_compose=/opt/harmony-resolver/compose.prod.yaml
  if [ -r "$legacy_environment" ] && [ -r "$legacy_compose" ]; then
    docker compose --env-file "$legacy_environment" -f "$legacy_compose" exec -T postgres \
      pg_dump -U harmony -d harmony -Fc > "$backup_directory/resolver-$timestamp.dump"
  fi
  echo "Stopping the legacy Resolver-owned stack for Platform cutover."
  systemctl stop harmony-resolver.service
  systemctl disable harmony-resolver.service
fi

previous_resolver_image="$(
  docker inspect --format '{{.Config.Image}}' \
    "$(docker compose --env-file "$environment_file" -f compose.prod.yaml ps -q resolver-api-1 2>/dev/null)" \
    2>/dev/null || true
)"
previous_cloud_image="$(
  docker inspect --format '{{.Config.Image}}' \
    "$(docker compose --env-file "$environment_file" -f compose.prod.yaml ps -q cloud-api 2>/dev/null)" \
    2>/dev/null || true
)"
if docker compose --env-file "$environment_file" -f compose.prod.yaml ps postgres --status running --quiet | grep -q .; then
  docker compose --env-file "$environment_file" -f compose.prod.yaml exec -T postgres \
    pg_dump -U harmony -d harmony -Fc > "$backup_directory/resolver-$timestamp.dump"
  if docker compose --env-file "$environment_file" -f compose.prod.yaml exec -T postgres \
      psql -U harmony -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='harmony_cloud'" | grep -q 1; then
    docker compose --env-file "$environment_file" -f compose.prod.yaml exec -T postgres \
      pg_dump -U harmony -d harmony_cloud -Fc > "$backup_directory/cloud-$timestamp.dump"
  fi
fi

docker compose --env-file "$environment_file" -f compose.prod.yaml pull
docker compose --env-file "$environment_file" -f compose.prod.yaml up -d --remove-orphans

: "${DOWNLOADER_RABBITMQ_PASSWORD:?DOWNLOADER_RABBITMQ_PASSWORD is required}"
if docker compose --env-file "$environment_file" -f compose.prod.yaml exec -T rabbitmq \
    rabbitmqctl -q list_users | awk '{print $1}' | grep -qx downloader; then
  docker compose --env-file "$environment_file" -f compose.prod.yaml exec -T rabbitmq \
    rabbitmqctl change_password downloader "$DOWNLOADER_RABBITMQ_PASSWORD"
else
  docker compose --env-file "$environment_file" -f compose.prod.yaml exec -T rabbitmq \
    rabbitmqctl add_user downloader "$DOWNLOADER_RABBITMQ_PASSWORD"
fi
docker compose --env-file "$environment_file" -f compose.prod.yaml exec -T rabbitmq \
  rabbitmqctl set_permissions -p / downloader \
  '^harmony\.ingest\.jobs$' '^$' '^harmony\.ingest\.jobs$'

if ! curl --fail --silent --show-error --retry 20 --retry-delay 3 \
    https://harmony-resolver.duckdns.org/health/ready >/dev/null \
  || ! curl --fail --silent --show-error --retry 20 --retry-delay 3 \
    https://harmony-resolver.duckdns.org/cloud/health/live >/dev/null; then
  if [ -n "$previous_resolver_image" ] && [ -n "$previous_cloud_image" ]; then
    echo "Health check failed; restoring previous service images." >&2
    RESOLVER_IMAGE="$previous_resolver_image" CLOUD_IMAGE="$previous_cloud_image" \
      docker compose --env-file "$environment_file" -f compose.prod.yaml \
      up -d --remove-orphans resolver-api-1 resolver-api-2 cloud-api nginx caddy
  fi
  exit 1
fi
