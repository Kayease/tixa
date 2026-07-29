#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${TIXA_REPOSITORY:-Kayease/tixa}"
VERSION="${TIXA_VERSION:-main}"
REPOSITORY_URL="${TIXA_REPO_URL:-https://github.com/${REPOSITORY}.git}"

fail() {
  echo "Tixa installation failed: $1" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "run as root (example: curl ... | sudo bash)"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v tar >/dev/null 2>&1 || fail "tar is required"

case "$VERSION" in
  main)
    ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/heads/main.tar.gz"
    ;;
  v[0-9]*|[0-9]*)
    ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/tags/${VERSION}.tar.gz"
    ;;
  *)
    fail "invalid TIXA_VERSION '$VERSION'; use main or a release tag"
    ;;
esac

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
