#!/usr/bin/env bash
set -euo pipefail

platform_directory=/opt/harmony-platform
resolver_image="${1:-}"
cloud_image="${2:-}"
# Optional: reasserted into the runtime env file on every deploy so a value set
# once in GitHub Actions secrets never needs a manual edit on the box again.
# Omit (empty string) to leave whatever is already on disk untouched.
admin_auth0_client_id="${3:-}"

if [ "$#" -ne 3 ]; then
  echo "Expected the two immutable Harmony image references plus an admin console Auth0 client id (may be empty)." >&2
  exit 1
fi
if [[ ! "$resolver_image" =~ ^ghcr\.io/bozmund/harmony-resolver-api:(latest|sha-[0-9a-f]{40})$ ]]; then
  echo "Invalid Resolver image reference." >&2
  exit 1
fi
if [[ ! "$cloud_image" =~ ^ghcr\.io/bozmund/harmony-cloud-api:(latest|sha-[0-9a-f]{40})$ ]]; then
  echo "Invalid Cloud image reference." >&2
  exit 1
fi
# Auth0 client ids are base62; this also accepts empty, meaning "leave it alone".
if [[ -n "$admin_auth0_client_id" && ! "$admin_auth0_client_id" =~ ^[A-Za-z0-9]{1,64}$ ]]; then
  echo "Invalid admin console Auth0 client id." >&2
  exit 1
fi

test -d "$platform_directory/.git"
test "$(stat -c '%U:%G' "$platform_directory")" = "root:root"

git -C "$platform_directory" pull --ff-only

export RESOLVER_IMAGE="$resolver_image"
export CLOUD_IMAGE="$cloud_image"
export ADMIN_AUTH0_CLIENT_ID="$admin_auth0_client_id"
exec /usr/bin/bash "$platform_directory/scripts/deploy.sh"
