#!/usr/bin/env bash
set -euo pipefail

workspace="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment_file="${HARMONY_ENV_FILE:-/etc/harmony-platform/harmony-platform.env}"
backup_directory="${HARMONY_BACKUP_DIR:-/var/backups/harmony-platform}"

test -r "$environment_file"
mkdir -p "$backup_directory"

# Reasserts CI/CD-sourced config into the persistent, root-owned env file, so
# a value set once as a GitHub Actions secret never needs a manual edit here
# again. Empty means "not supplied this run" — leave whatever is on disk.
set_persistent_value() {
  local key="$1" value="$2"
  test -n "$value" || return 0
  if grep -q "^$key=" "$environment_file"; then
    sed -i "s|^$key=.*|$key=$value|" "$environment_file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$environment_file"
  fi
}
set_persistent_value ADMIN_AUTH0_CLIENT_ID "${ADMIN_AUTH0_CLIENT_ID:-}"

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
# Both proxies mount their config from the repo by bind mount, and `up -d`
# alone will not restart them: editing Caddyfile or the nginx config changes
# no container-level setting, so Compose sees nothing to do. Worse, `git pull`
# replaces those files atomically — the new file is a new inode, while the
# running container's bind mount still resolves to the old one. A `caddy
# reload` does not help either; it re-reads the same stale inode.
#
# This is not hypothetical: the /mcp route sat unrouted for four weeks and
# every deploy in that window happily reported success while Caddy served a
# config from before the route existed. Recreating both on every deploy is
# cheap (a second of proxy downtime) and is the only thing that reliably
# picks up a config edit.
docker compose --env-file "$environment_file" -f compose.prod.yaml \
  up -d --no-deps --force-recreate nginx caddy

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
