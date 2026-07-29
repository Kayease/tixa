#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${TIXA_REPOSITORY:-Kayease/tixa}"
VERSION="${TIXA_VERSION:-stable}"
REPOSITORY_URL="${TIXA_REPO_URL:-https://github.com/${REPOSITORY}.git}"

fail() {
  echo "Tixa installation failed: $1" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "run as root (example: curl ... | sudo bash)"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"

if [ "$VERSION" = "stable" ]; then
  LATEST_URL="$(curl --fail --silent --show-error --location --output /dev/null --write-out '%{url_effective}' \
    "https://github.com/${REPOSITORY}/releases/latest")" || fail "no stable GitHub release is available"
  VERSION="${LATEST_URL##*/}"
  [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "latest release has an invalid tag: $VERSION"
  ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/tags/${VERSION}.tar.gz"
elif [ "$VERSION" = "main" ]; then
  ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/heads/main.tar.gz"
elif [[ "$VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  if [[ "$VERSION" != v* ]]; then VERSION="v$VERSION"; fi
  ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/tags/${VERSION}.tar.gz"
else
  fail "invalid TIXA_VERSION '$VERSION'; use stable, main, or a tag such as v1.2.0"
fi

INSTALL_DIR="$(mktemp -d /tmp/tixa-bootstrap.XXXXXX)"
trap 'rm -rf "$INSTALL_DIR"' EXIT
mkdir -p "$INSTALL_DIR/repository"

echo "Downloading Tixa ${VERSION} from GitHub..."
curl --fail --silent --show-error --location --retry 3 \
  "$ARCHIVE_URL" -o "$INSTALL_DIR/tixa.tar.gz"

tar -xzf "$INSTALL_DIR/tixa.tar.gz" \
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
echo "Tixa is ready. Run: sudo tixa create"
