#!/usr/bin/env bash
set -e

PROJECT="$1"
MODE="$2"

STATE_DIR="/var/lib/tixa"
REGISTRY="$STATE_DIR/registry.json"

if [ -z "$PROJECT" ]; then
  echo "❌ Project name required"
  echo "👉 Usage: tixa delete <project>"
  exit 1
fi

if [ ! -f "$REGISTRY" ]; then
  echo "❌ Registry not found"
  echo "👉 Cannot safely delete service"
  exit 1
fi

if ! jq -e ".\"$PROJECT\"" "$REGISTRY" >/dev/null; then
  echo "❌ Project '$PROJECT' not found"
  echo "👉 Run: tixa list"
  exit 1
fi

DOMAIN=$(jq -r ".\"$PROJECT\".domain" "$REGISTRY")

echo ""
echo "🗑️  TIXA · DELETE SERVICE"
echo "---------------------------"
echo "Project : $PROJECT"
echo "Domain  : $DOMAIN"
echo "---------------------------"

if [ "$MODE" != "--force" ]; then
  echo ""
  read -p "Type DELETE to confirm: " CONFIRM
  if [ "$CONFIRM" != "DELETE" ]; then
    echo "❌ Cancelled"
    exit 1
  fi
fi

echo ""
echo "▶ Stopping systemd service"
systemctl stop "${PROJECT}-processor" || true
systemctl disable "${PROJECT}-processor" || true
rm -f "/etc/systemd/system/${PROJECT}-processor.service"
systemctl daemon-reload

echo "▶ Removing application files"
rm -rf "/opt/${PROJECT}-processor"

echo "▶ Removing media files"
rm -rf "/var/www/images/$PROJECT"

echo "▶ Removing nginx config"
rm -f "/etc/nginx/sites-enabled/${PROJECT}.conf"
rm -f "/etc/nginx/sites-available/${PROJECT}.conf"
systemctl reload nginx

echo "▶ Removing SSL certificate (if exists)"
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  certbot delete \
    --cert-name "$DOMAIN" \
    --non-interactive || true
fi

echo "▶ Updating registry"
jq "del(.\"$PROJECT\")" "$REGISTRY" > /tmp/tixa_registry.json
mv /tmp/tixa_registry.json "$REGISTRY"

echo ""
echo "✅ Service '$PROJECT' deleted completely"
echo "🧹 No residue left behind"
