#!/usr/bin/env bash
set -e

# Resolve the repository from this script's location. This allows the cloned
# repository to live anywhere during installation.
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="/opt/tixa"
STATE_DIR="/var/lib/tixa"

REGISTRY_FILE="$STATE_DIR/registry.json"
SSL_EMAIL_FILE="$STATE_DIR/sslemail"

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: run this installer as root: sudo bash install.sh"
  exit 1
fi

if [ ! -r /etc/os-release ]; then
  echo "Error: cannot identify this operating system"
  exit 1
fi

# Tixa currently supports Debian-family servers. Install only packages that
# are not already present, leaving existing package configuration unchanged.
. /etc/os-release
case "${ID:-}:${ID_LIKE:-}" in
  *debian*|*ubuntu*) ;;
  *)
    echo "Error: unsupported OS '${PRETTY_NAME:-unknown}'. Tixa supports Debian/Ubuntu."
    exit 1
    ;;
esac

REQUIRED_PACKAGES=(
  python3 python3-pip python3-venv
  nginx certbot python3-certbot-nginx
  ffmpeg libvips-dev libmagic1
  jq dnsutils curl openssl git ca-certificates
)
MISSING_PACKAGES=()

for PACKAGE in "${REQUIRED_PACKAGES[@]}"; do
  if ! dpkg-query -W -f='${Status}' "$PACKAGE" 2>/dev/null | grep -q '^install ok installed$'; then
    MISSING_PACKAGES+=("$PACKAGE")
  fi
done

if [ "${#MISSING_PACKAGES[@]}" -gt 0 ]; then
  echo "Installing required system packages: ${MISSING_PACKAGES[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends "${MISSING_PACKAGES[@]}"
else
  echo "All required system packages are already installed"
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
  echo "Error: Python virtual environments are unavailable after installing python3-venv"
  exit 1
fi

systemctl enable --now nginx

for REQUIRED_DIR in cli core templates; do
  if [ ! -d "$REPO_DIR/$REQUIRED_DIR" ]; then
    echo "Error: missing required directory: $REPO_DIR/$REQUIRED_DIR"
    exit 1
  fi
done

echo "▶ Installing Tixa..."
echo ""

# --------------------------------------------------
# Persistent state (SAFE, never wiped on reinstall)
# --------------------------------------------------
mkdir -p "$STATE_DIR"

# -------------------------
# Registry (create once)
# -------------------------
if [ ! -f "$REGISTRY_FILE" ]; then
  echo "{}" > "$REGISTRY_FILE"
  chmod 600 "$REGISTRY_FILE"
  echo "✅ Registry initialized"
else
  echo "✅ Registry exists"
fi

# -------------------------
# SSL Email (one-time setup)
# -------------------------
if [ ! -f "$SSL_EMAIL_FILE" ]; then
  echo ""
  echo "🔐 SSL CERTIFICATE SETUP (ONE-TIME)"
  echo "----------------------------------------"
  echo "Tixa automatically secures your media services"
  echo "with HTTPS using Let's Encrypt (via Certbot)."
  echo ""
  echo "📧 Why this email is required:"
  echo "• SSL expiry reminders (important)"
  echo "• Security & revocation notices"
  echo "• Certificate recovery if needed"
  echo ""
  echo "✅ This email is:"
  echo "• Asked ONLY once during installation"
  echo "• Stored securely on this server"
  echo "• Reused automatically for all services"
  echo ""
  echo "🛠 You can update it later anytime using:"
  echo "  tixa sslemail set"
  echo ""

  read -p "Enter email for SSL certificates: " SSL_EMAIL

  if [[ -z "$SSL_EMAIL" ]]; then
    echo "❌ SSL email is required to continue"
    exit 1
  fi

  echo "$SSL_EMAIL" > "$SSL_EMAIL_FILE"
  chmod 600 "$SSL_EMAIL_FILE"

  echo ""
  echo "✅ SSL email saved successfully"
  echo "🔁 Tixa will auto-install & auto-renew HTTPS certificates"
else
  echo "✅ SSL email already configured: $(cat "$SSL_EMAIL_FILE")"
fi

# --------------------------------------------------
# Runtime install (safe to replace on upgrade). Stage files first so this also
# works if the repository itself happens to be located at /opt/tixa.
# --------------------------------------------------
STAGING_DIR="$(mktemp -d /tmp/tixa-install.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -r "$REPO_DIR/cli" "$STAGING_DIR/"
cp -r "$REPO_DIR/core" "$STAGING_DIR/"
cp -r "$REPO_DIR/templates" "$STAGING_DIR/"
printf '%s\n' "${TIXA_REPO_URL:-https://github.com/Kayease/tixa.git}" > "$STAGING_DIR/repository-url"

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"

cp -r "$STAGING_DIR/cli" "$RUNTIME_DIR/"
cp -r "$STAGING_DIR/core" "$RUNTIME_DIR/"
cp -r "$STAGING_DIR/templates" "$RUNTIME_DIR/"
cp "$STAGING_DIR/repository-url" "$RUNTIME_DIR/repository-url"

chmod +x "$RUNTIME_DIR/cli/"*
chmod +x "$RUNTIME_DIR/core/"*

# --------------------------------------------------
# CLI launcher
# --------------------------------------------------
ln -sf "$RUNTIME_DIR/cli/tixa" /usr/local/bin/tixa
chmod +x /usr/local/bin/tixa

# --------------------------------------------------
# Final output
# --------------------------------------------------
echo ""
echo "✅ Tixa installed successfully"
echo "----------------------------------------"
echo "📂 State directory : $STATE_DIR"
echo "📄 Registry file  : $REGISTRY_FILE"
echo "📧 SSL email file : $SSL_EMAIL_FILE"
echo ""
echo "Next steps:"
echo "  tixa create"
echo ""
echo "Run: tixa"
