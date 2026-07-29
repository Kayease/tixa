#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${TIXA_REPOSITORY:-Kayease/tixa}"
VERSION="${TIXA_VERSION:-stable}"
REPOSITORY_URL="${TIXA_REPO_URL:-https://github.com/${REPOSITORY}.git}"
# Set TIXA_SHA256 to pin the expected archive digest yourself.
EXPECTED_SHA256="${TIXA_SHA256:-}"

fail() {
  echo "Tixa installation failed: $1" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "run as root (example: curl ... | sudo bash)"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

RELEASE_ASSET=""

if [ "$VERSION" = "stable" ]; then
  LATEST_URL="$(curl --fail --silent --show-error --location --output /dev/null --write-out '%{url_effective}' \
    "https://github.com/${REPOSITORY}/releases/latest")" || fail "no stable GitHub release is available"
  VERSION="${LATEST_URL##*/}"
  [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "latest release has an invalid tag: $VERSION"
  ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/tags/${VERSION}.tar.gz"
  RELEASE_ASSET="https://github.com/${REPOSITORY}/releases/download/${VERSION}"
elif [ "$VERSION" = "main" ]; then
  ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/heads/main.tar.gz"
elif [[ "$VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  if [[ "$VERSION" != v* ]]; then VERSION="v$VERSION"; fi
  ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/tags/${VERSION}.tar.gz"
  RELEASE_ASSET="https://github.com/${REPOSITORY}/releases/download/${VERSION}"
else
  fail "invalid TIXA_VERSION '$VERSION'; use stable, main, or a tag such as v1.2.0"
fi

INSTALL_DIR="$(mktemp -d /tmp/tixa-bootstrap.XXXXXX)"
trap 'rm -rf "$INSTALL_DIR"' EXIT
mkdir -p "$INSTALL_DIR/repository"

ARCHIVE="$INSTALL_DIR/tixa.tar.gz"
VERIFIED=""

# --------------------------------------------------------------------------
# Prefer the signed-off release asset, whose digest is published in SHA256SUMS
# alongside it. HTTPS alone authenticates the host, not the bytes: it cannot
# tell you that the archive is the one that was released.
# --------------------------------------------------------------------------
if [ -n "$RELEASE_ASSET" ] && [ -z "$EXPECTED_SHA256" ]; then
  if curl --fail --silent --show-error --location --retry 3 \
      "${RELEASE_ASSET}/SHA256SUMS" -o "$INSTALL_DIR/SHA256SUMS" 2>/dev/null; then
    EXPECTED_SHA256="$(awk -v name="tixa-${VERSION}.tar.gz" \
      '$2 == name || $2 == "*" name {print $1}' "$INSTALL_DIR/SHA256SUMS" | head -n 1)"
    if [ -n "$EXPECTED_SHA256" ]; then
      ARCHIVE_URL="${RELEASE_ASSET}/tixa-${VERSION}.tar.gz"
    fi
  fi
fi

echo "Downloading Tixa ${VERSION} from GitHub..."
curl --fail --silent --show-error --location --retry 3 \
  "$ARCHIVE_URL" -o "$ARCHIVE"

if [ -n "$EXPECTED_SHA256" ]; then
  ACTUAL_SHA256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
  if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    fail "archive checksum mismatch
  expected: $EXPECTED_SHA256
  actual:   $ACTUAL_SHA256
The download was corrupted or tampered with. Nothing has been installed."
  fi
  VERIFIED="yes"
  echo "Checksum verified: $ACTUAL_SHA256"
else
  echo "Warning: no published checksum for ${VERSION}; the archive could not be verified." >&2
  echo "         Pin one with TIXA_SHA256=<digest> for a verified install." >&2
fi

tar -xzf "$ARCHIVE" \
  --strip-components=1 \
  -C "$INSTALL_DIR/repository"

[ -f "$INSTALL_DIR/repository/install.sh" ] || fail "downloaded archive does not contain install.sh"
[ -d "$INSTALL_DIR/repository/cli" ] || fail "downloaded archive is incomplete (cli missing)"
[ -d "$INSTALL_DIR/repository/core" ] || fail "downloaded archive is incomplete (core missing)"
[ -d "$INSTALL_DIR/repository/templates" ] || fail "downloaded archive is incomplete (templates missing)"
[ -f "$INSTALL_DIR/repository/VERSION" ] || fail "downloaded archive is incomplete (VERSION missing)"

ARCHIVE_VERSION="$(tr -d '[:space:]' < "$INSTALL_DIR/repository/VERSION")"
if [ "$VERSION" != "main" ] && [ "${VERSION#v}" != "$ARCHIVE_VERSION" ]; then
  fail "release tag '$VERSION' contains VERSION '$ARCHIVE_VERSION'"
fi

echo "Starting Tixa's compatibility check and installer..."
if [ -n "${TIXA_SSL_EMAIL:-}" ]; then
  TIXA_REPO_URL="$REPOSITORY_URL" bash "$INSTALL_DIR/repository/install.sh"
elif [ -r /dev/tty ]; then
  TIXA_REPO_URL="$REPOSITORY_URL" bash "$INSTALL_DIR/repository/install.sh" </dev/tty
else
  fail "no interactive terminal; set TIXA_SSL_EMAIL for unattended installation"
fi

echo ""
if [ -n "$VERIFIED" ]; then
  echo "Tixa ${VERSION} is ready (checksum verified). Run: sudo tixa create"
else
  echo "Tixa ${VERSION} is ready. Run: sudo tixa create"
fi
