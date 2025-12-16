#!/usr/bin/env bash
set -e

REPO_DIR="/var/www/Project/tixa"
BASE_DIR="/opt/tixa"
CERTBOT_EMAIL_FILE="$BASE_DIR/.certbot_email"

echo "▶ Installing Tixa..."

# Remove old install
rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"

# Copy runtime files
cp -r "$REPO_DIR/cli" "$BASE_DIR/"
cp -r "$REPO_DIR/core" "$BASE_DIR/"
cp -r "$REPO_DIR/templates" "$BASE_DIR/"
cp -r "$REPO_DIR/registry" "$BASE_DIR/"

# Permissions
chmod +x "$BASE_DIR/cli/"*
chmod +x "$BASE_DIR/core/"*

# Certbot email (ask only once)
if [ ! -f "$CERTBOT_EMAIL_FILE" ]; then
  echo ""
  read -p "Enter email for SSL (Certbot): " CERTBOT_EMAIL

  if [[ -z "$CERTBOT_EMAIL" ]]; then
    echo "❌ Email is required for SSL certificates"
    exit 1
  fi

  echo "$CERTBOT_EMAIL" > "$CERTBOT_EMAIL_FILE"
  chmod 600 "$CERTBOT_EMAIL_FILE"
  echo "✅ Certbot email saved"
else
  echo "✅ Certbot email already configured: $(cat "$CERTBOT_EMAIL_FILE")"
fi

# Ensure registry file exists
if [ ! -f "$BASE_DIR/registry/services.json" ]; then
  echo "{}" > "$BASE_DIR/registry/services.json"
fi

# Install CLI launcher
ln -sf "$REPO_DIR/cli/tixa" /usr/local/bin/tixa
chmod +x /usr/local/bin/tixa

echo ""
echo "✅ Tixa installed successfully"
echo "Run: tixa"
