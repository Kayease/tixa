#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/tixa"
REPOSITORY_FILE="$BASE_DIR/repository-url"
TARGET="${1:-${TIXA_UPDATE_VERSION:-stable}}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: run this command as root: sudo tixa self-update"
  exit 1
fi

if [ ! -f "$REPOSITORY_FILE" ]; then
  echo "Error: update source is not configured. Re-run install.sh from a current clone."
  exit 1
fi

REPOSITORY_URL="$(cat "$REPOSITORY_FILE")"

if [ "$TARGET" = "stable" ]; then
  TARGET="$(git ls-remote --tags --refs "$REPOSITORY_URL" 'v*' \
    | awk -F/ '{print $3}' | sort -V | tail -n 1)"
  if [ -z "$TARGET" ]; then
    echo "Error: no stable Tixa release tags were found."
    exit 1
  fi
fi

if [ "$TARGET" = "main" ]; then
  :
elif [[ "$TARGET" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  :
elif [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  TARGET="v$TARGET"
else
  echo "Error: invalid version '$TARGET'. Use stable, main, or a tag such as v1.2.0."
  exit 1
fi

UPDATE_DIR="$(mktemp -d /tmp/tixa-update.XXXXXX)"
trap 'rm -rf "$UPDATE_DIR"' EXIT

echo "Downloading Tixa $TARGET from $REPOSITORY_URL..."
git clone --quiet --depth 1 --branch "$TARGET" "$REPOSITORY_URL" "$UPDATE_DIR/repository"

# install.sh replaces only /opt/tixa. Persistent registry data remains in
# /var/lib/tixa, and generated services remain in /opt/*-processor.
TIXA_REPO_URL="$REPOSITORY_URL" bash "$UPDATE_DIR/repository/install.sh"

echo "Tixa CLI updated successfully"
"$BASE_DIR/cli/tixa" version
echo "Run 'sudo tixa update --all' to deploy new templates to existing services."
