#!/usr/bin/env bash
set -e

REPO_DIR="/var/www/Project/tixa"
RUNTIME_DIR="/opt/tixa"
STATE_DIR="/var/lib/tixa"
REGISTRY_FILE="$STATE_DIR/registry.json"
SSL_EMAIL_FILE="$STATE_DIR/sslemail"

echo "▶ Installing Tixa..."

# --------------------------------------------------
# Persistent state (SAFE, never wiped on reinstall)
# --------------------------------------------------
mkdir -p "$STATE_DIR"

# Registry (create only if missing)
if [ ! -f "$REGISTRY_FILE" ]; then
  echo "{}" > "$REGISTRY_FILE"
  chmod 600 "$REGISTRY_FILE"
  echo "✅ Registry initialized"
else
  echo "✅ Registry exists"
fi

# SSL email (ask only if missing)
if [ ! -f "$SSL_EMAIL_FILE" ]; then
  echo ""
  read -p "Enter email for SSL (Certbot): " SSL_EMAIL

  if [[ -z "$SSL_EMAIL" ]]; then
    echo "❌ SSL email is required"
    exit 1
  fi

  echo "$SSL_EMAIL" > "$SSL_EMAIL_FILE"
  chmod 600 "$SSL_EMAIL_FILE"
  echo "✅ SSL email saved"
else
  echo "✅ SSL email already configured: $(cat "$SSL_EMAIL_FILE")"
fi

# --------------------------------------------------
# Runtime install (safe to replace)
# --------------------------------------------------
rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"

cp -r "$REPO_DIR/cli" "$RUNTIME_DIR/"
cp -r "$REPO_DIR/core" "$RUNTIME_DIR/"
cp -r "$REPO_DIR/templates" "$RUNTIME_DIR/"

chmod +x "$RUNTIME_DIR/cli/"*
chmod +x "$RUNTIME_DIR/core/"*

# --------------------------------------------------
# CLI launcher
# --------------------------------------------------
ln -sf "$REPO_DIR/cli/tixa" /usr/local/bin/tixa
chmod +x /usr/local/bin/tixa

echo ""
echo "✅ Tixa installed successfully"
echo "📂 State directory : $STATE_DIR"
echo "📄 Registry file  : $REGISTRY_FILE"
echo "📧 SSL email file : $SSL_EMAIL_FILE"
echo ""
echo "Run: tixa"
