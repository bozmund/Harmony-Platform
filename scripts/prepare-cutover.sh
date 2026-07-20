#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root." >&2
  exit 1
fi
if [ "${1:-}" != "PREPARE-HARMONY-CUTOVER" ] || [ "$#" -ne 1 ]; then
  echo "Explicit PREPARE-HARMONY-CUTOVER confirmation is required." >&2
  exit 1
fi

backup_directory=/var/backups/harmony-platform
install -d -m 700 "$backup_directory"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
legacy_environment=/etc/harmony-resolver/harmony-resolver.env
legacy_compose=/opt/harmony-resolver/compose.prod.yaml

if [ -r "$legacy_environment" ] && [ -r "$legacy_compose" ]; then
  docker compose --env-file "$legacy_environment" -f "$legacy_compose" up -d postgres
  postgres_ready=false
  for _ in $(seq 1 30); do
    if docker compose --env-file "$legacy_environment" -f "$legacy_compose" exec -T postgres \
        pg_isready -U harmony -d harmony >/dev/null; then
      postgres_ready=true
      break
    fi
    sleep 2
  done
  if [ "$postgres_ready" != "true" ]; then
    echo "Legacy PostgreSQL did not become ready; refusing cutover." >&2
    exit 1
  fi
  docker compose --env-file "$legacy_environment" -f "$legacy_compose" exec -T postgres \
    pg_dump -U harmony -d harmony -Fc >"$backup_directory/resolver-$timestamp.dump"
  test -s "$backup_directory/resolver-$timestamp.dump"
  echo "PostgreSQL backup created at $backup_directory/resolver-$timestamp.dump"
elif docker volume inspect harmony-resolver_postgres >/dev/null 2>&1; then
  echo "Resolver PostgreSQL volume exists but legacy configuration is unavailable." >&2
  echo "Refusing cutover because a verified database backup cannot be created." >&2
  exit 1
fi

systemctl stop harmony-resolver.service 2>/dev/null || true
systemctl disable harmony-resolver.service 2>/dev/null || true

if command -v docker >/dev/null 2>&1; then
  mapfile -t harmony_containers < <(
    {
      docker ps -aq --filter label=com.docker.compose.project=harmony-resolver
      docker ps -aq --filter label=com.docker.compose.project=harmony-platform
    } | sort -u
  )
  if [ "${#harmony_containers[@]}" -gt 0 ]; then
    docker rm -f "${harmony_containers[@]}"
  fi

  harmony_networks=(
    harmony-resolver_default
    harmony-platform_default
  )
  for network in "${harmony_networks[@]}"; do
    docker network rm "$network" 2>/dev/null || true
  done
fi

harmony_directories=(
  /opt/harmony-resolver
  /opt/harmony-platform
)
for target in "${harmony_directories[@]}"; do
  resolved_target="$(realpath -m -- "$target")"
  if [ "$resolved_target" != "$target" ]; then
    echo "Refusing unexpected reset target: $resolved_target" >&2
    exit 1
  fi
  rm -rf -- "$target"
done

rm -f \
  /etc/systemd/system/harmony-resolver.service \
  /etc/sudoers.d/harmony-resolver-deploy \
  /etc/sudoers.d/harmony-platform-deploy \
  /usr/local/sbin/harmony-platform-deploy
systemctl daemon-reload

echo "Harmony containers and old checkouts were removed."
echo "All named volumes, legacy credentials and database backups were preserved for Platform bootstrap."
