#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/tixa"
REPOSITORY_FILE="$BASE_DIR/repository-url"
TARGET="${1:-${TIXA_UPDATE_VERSION:-stable}}"
# Set TIXA_SHA256 to pin the expected archive digest yourself.
EXPECTED_SHA256="${TIXA_SHA256:-}"

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

# Derive the owner/repo slug so the published checksum can be located.
SLUG="$(printf '%s' "$REPOSITORY_URL" | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"

echo "Downloading Tixa $TARGET from $REPOSITORY_URL..."

FETCHED=""
if [ "$TARGET" != "main" ] && [[ "$SLUG" =~ ^[^/]+/[^/]+$ ]] && command -v sha256sum >/dev/null 2>&1; then
  ASSET_BASE="https://github.com/${SLUG}/releases/download/${TARGET}"
  ARCHIVE="$UPDATE_DIR/tixa.tar.gz"

  if [ -z "$EXPECTED_SHA256" ] && curl --fail --silent --show-error --location --retry 3 \
      "${ASSET_BASE}/SHA256SUMS" -o "$UPDATE_DIR/SHA256SUMS" 2>/dev/null; then
    EXPECTED_SHA256="$(awk -v name="tixa-${TARGET}.tar.gz" \
      '$2 == name || $2 == "*" name {print $1}' "$UPDATE_DIR/SHA256SUMS" | head -n 1)"
  fi

  if [ -n "$EXPECTED_SHA256" ] && curl --fail --silent --show-error --location --retry 3 \
      "${ASSET_BASE}/tixa-${TARGET}.tar.gz" -o "$ARCHIVE" 2>/dev/null; then
    ACTUAL_SHA256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
    if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
      echo "Error: archive checksum mismatch for $TARGET" >&2
      echo "  expected: $EXPECTED_SHA256" >&2
      echo "  actual:   $ACTUAL_SHA256" >&2
      echo "Nothing has been changed." >&2
      exit 1
    fi
    mkdir -p "$UPDATE_DIR/repository"
    tar -xzf "$ARCHIVE" --strip-components=1 -C "$UPDATE_DIR/repository"
    echo "Checksum verified: $ACTUAL_SHA256"
    FETCHED="asset"
  fi
fi

if [ -z "$FETCHED" ]; then
  echo "Warning: no published checksum for $TARGET; falling back to an unverified git clone." >&2
  git clone --quiet --depth 1 --branch "$TARGET" "$REPOSITORY_URL" "$UPDATE_DIR/repository"
fi

[ -f "$UPDATE_DIR/repository/install.sh" ] || { echo "Error: downloaded source has no install.sh" >&2; exit 1; }

# install.sh replaces only /opt/tixa. Persistent registry data remains in
# /var/lib/tixa, and generated services remain in /opt/*-processor.
TIXA_REPO_URL="$REPOSITORY_URL" bash "$UPDATE_DIR/repository/install.sh"

echo "Tixa CLI updated successfully"
"$BASE_DIR/cli/tixa" version
echo "Run 'sudo tixa update --all' to deploy new templates to existing services."
