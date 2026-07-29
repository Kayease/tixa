#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/tixa"
REPOSITORY_FILE="$BASE_DIR/repository-url"
BRANCH="${TIXA_UPDATE_BRANCH:-main}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: run this command as root: sudo tixa self-update"
  exit 1
fi

if [ ! -f "$REPOSITORY_FILE" ]; then
  echo "Error: update source is not configured. Re-run install.sh from a current clone."
  exit 1
fi

REPOSITORY_URL="$(cat "$REPOSITORY_FILE")"
UPDATE_DIR="$(mktemp -d /tmp/tixa-update.XXXXXX)"
trap 'rm -rf "$UPDATE_DIR"' EXIT

echo "Downloading the latest Tixa CLI from $REPOSITORY_URL ($BRANCH)..."
git clone --quiet --depth 1 --branch "$BRANCH" "$REPOSITORY_URL" "$UPDATE_DIR/repository"

# install.sh replaces only /opt/tixa. Persistent registry data remains in
# /var/lib/tixa, and generated services remain in /opt/*-processor.
TIXA_REPO_URL="$REPOSITORY_URL" bash "$UPDATE_DIR/repository/install.sh"

echo "Tixa CLI updated successfully"
echo "Run 'sudo tixa update --all' to deploy new templates to existing services."
