#!/usr/bin/env bash
set -e

REPO_DIR="/var/www/Project/tixa"
RUNTIME_DIR="/opt/tixa"
STATE_DIR="/var/lib/tixa"

REGISTRY_FILE="$STATE_DIR/registry.json"
SSL_EMAIL_FILE="$STATE_DIR/sslemail"

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
# Runtime install (safe to replace on upgrade)
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
