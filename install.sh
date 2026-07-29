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

# Reject incompatible hosts before installing or changing any packages.
if [ ! -r /proc/1/comm ] || [ "$(</proc/1/comm)" != "systemd" ]; then
  echo "Error: systemd is not running as PID 1. Tixa requires a systemd-based VPS."
  exit 1
fi

for COMPETING_SERVICE in apache2 caddy lighttpd; do
  if systemctl is-active --quiet "$COMPETING_SERVICE" 2>/dev/null; then
    echo "Error: competing web server '$COMPETING_SERVICE' is active."
    echo "Tixa manages Nginx and will not modify or disable an existing web server."
    exit 1
  fi
done

if command -v ss >/dev/null 2>&1; then
  EXISTING_HTTP_LISTENERS="$(ss -ltnp 2>/dev/null | awk '$4 ~ /:80$|:443$/ {print}' || true)"
  if [ -n "$EXISTING_HTTP_LISTENERS" ] && ! grep -q 'nginx' <<< "$EXISTING_HTTP_LISTENERS"; then
    echo "Error: ports 80/443 are already used by a non-Nginx process:"
    echo "$EXISTING_HTTP_LISTENERS"
    echo "Tixa has not installed or changed any packages."
    exit 1
  fi
fi

if command -v nginx >/dev/null 2>&1 && ! nginx -t >/dev/null 2>&1; then
  echo "Error: the existing Nginx configuration is invalid."
  echo "Run 'sudo nginx -t' for details. Tixa has not changed any packages."
  exit 1
fi

REQUIRED_PACKAGES=(
  python3 python3-pip python3-venv
  nginx certbot python3-certbot-nginx
  ffmpeg libvips-tools libmagic1
  jq dnsutils curl openssl git ca-certificates iproute2 procps
)
MISSING_PACKAGES=()

for PACKAGE in "${REQUIRED_PACKAGES[@]}"; do
  if ! dpkg-query -W -f='${Status}' "$PACKAGE" 2>/dev/null | grep -q '^install ok installed$'; then
    MISSING_PACKAGES+=("$PACKAGE")
  fi
done

if [ "${#MISSING_PACKAGES[@]}" -gt 0 ]; then
  echo "Checking package compatibility: ${MISSING_PACKAGES[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update

  APT_SIMULATION_LOG="$(mktemp /tmp/tixa-apt-check.XXXXXX)"
  if ! apt-get install --simulate --no-install-recommends "${MISSING_PACKAGES[@]}" >"$APT_SIMULATION_LOG" 2>&1; then
    echo "Error: required packages cannot be installed safely on this server:"
    cat "$APT_SIMULATION_LOG"
    rm -f "$APT_SIMULATION_LOG"
    exit 1
  fi
  rm -f "$APT_SIMULATION_LOG"

  echo "Compatibility passed. Installing missing packages: ${MISSING_PACKAGES[*]}"
  apt-get install -y --no-install-recommends "${MISSING_PACKAGES[@]}"
else
  echo "All required system packages are already installed"
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
  echo "Error: Python virtual environments are unavailable after installing python3-venv"
  exit 1
fi

systemctl enable --now nginx

if ! bash "$REPO_DIR/core/doctor.sh" --quiet; then
  echo "Error: this server did not pass Tixa's compatibility check. No Tixa service was created."
  exit 1
fi

for REQUIRED_DIR in cli core templates; do
  if [ ! -d "$REPO_DIR/$REQUIRED_DIR" ]; then
    echo "Error: missing required directory: $REPO_DIR/$REQUIRED_DIR"
    exit 1
  fi
done

if [ ! -f "$REPO_DIR/VERSION" ]; then
  echo "Error: missing required file: $REPO_DIR/VERSION"
  exit 1
fi

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

  SSL_EMAIL="${TIXA_SSL_EMAIL:-}"
  if [ -z "$SSL_EMAIL" ]; then
    read -r -p "Enter email for SSL certificates: " SSL_EMAIL
  else
    echo "Using SSL email supplied by TIXA_SSL_EMAIL"
  fi

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
cp "$REPO_DIR/VERSION" "$STAGING_DIR/VERSION"
printf '%s\n' "${TIXA_REPO_URL:-https://github.com/Kayease/tixa.git}" > "$STAGING_DIR/repository-url"

# Build the new runtime beside the old one and swap with a rename. Deleting
# /opt/tixa before copying left the CLI missing entirely if the copy failed.
NEW_RUNTIME="${RUNTIME_DIR}.new-$$"
OLD_RUNTIME="${RUNTIME_DIR}.old-$$"

rm -rf "$NEW_RUNTIME" "$OLD_RUNTIME"
mkdir -p "$NEW_RUNTIME"

cp -r "$STAGING_DIR/cli" "$NEW_RUNTIME/"
cp -r "$STAGING_DIR/core" "$NEW_RUNTIME/"
cp -r "$STAGING_DIR/templates" "$NEW_RUNTIME/"
cp "$STAGING_DIR/VERSION" "$NEW_RUNTIME/VERSION"
cp "$STAGING_DIR/repository-url" "$NEW_RUNTIME/repository-url"

chmod +x "$NEW_RUNTIME/cli/"*
chmod +x "$NEW_RUNTIME/core/"*

RUNTIME_SWAPPED=0
restore_runtime() {
  if [ "$RUNTIME_SWAPPED" -eq 1 ] && [ ! -d "$RUNTIME_DIR" ] && [ -d "$OLD_RUNTIME" ]; then
    mv "$OLD_RUNTIME" "$RUNTIME_DIR"
    echo "Error: install failed; the previous Tixa runtime was restored."
  fi
  rm -rf "$STAGING_DIR" "$NEW_RUNTIME"
}
trap restore_runtime EXIT

if [ -d "$RUNTIME_DIR" ]; then
  mv "$RUNTIME_DIR" "$OLD_RUNTIME"
  RUNTIME_SWAPPED=1
fi
mv "$NEW_RUNTIME" "$RUNTIME_DIR"
rm -rf "$OLD_RUNTIME"
RUNTIME_SWAPPED=0

# --------------------------------------------------
# Shared Nginx rate-limit zones. The generated site configs reference these
# zones, so they must exist before any service config is validated.
# --------------------------------------------------
LIMITS_SOURCE="$RUNTIME_DIR/templates/limits.conf.tpl"
LIMITS_TARGET="/etc/nginx/conf.d/tixa-limits.conf"

if [ -f "$LIMITS_SOURCE" ] && command -v nginx >/dev/null 2>&1; then
  LIMITS_BACKUP=""
  if [ -f "$LIMITS_TARGET" ]; then
    LIMITS_BACKUP="$(mktemp /tmp/tixa-limits.XXXXXX)"
    cp "$LIMITS_TARGET" "$LIMITS_BACKUP"
  fi

  install -m 644 "$LIMITS_SOURCE" "$LIMITS_TARGET"

  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx >/dev/null 2>&1 || true
    echo "✅ Nginx rate-limit configuration installed"
  else
    echo "⚠️  Nginx rejected the Tixa rate-limit configuration; reverting it."
    if [ -n "$LIMITS_BACKUP" ]; then
      cp "$LIMITS_BACKUP" "$LIMITS_TARGET"
    else
      rm -f "$LIMITS_TARGET"
    fi
  fi

  [ -n "$LIMITS_BACKUP" ] && rm -f "$LIMITS_BACKUP"
fi

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
echo "  tixa version"
echo "  tixa create"
echo ""
echo "Run: tixa"
