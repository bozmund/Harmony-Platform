#!/usr/bin/env bash
set -euo pipefail

platform_directory=/opt/harmony-platform
resolver_image="${1:-}"
cloud_image="${2:-}"

if [ "$#" -ne 2 ]; then
  echo "Expected exactly two immutable Harmony image references." >&2
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

test -d "$platform_directory/.git"
test "$(stat -c '%U:%G' "$platform_directory")" = "root:root"

git -C "$platform_directory" pull --ff-only

export RESOLVER_IMAGE="$resolver_image"
export CLOUD_IMAGE="$cloud_image"
exec /usr/bin/bash "$platform_directory/scripts/deploy.sh"
