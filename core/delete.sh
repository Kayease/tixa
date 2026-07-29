#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-}"
MODE="${2:-}"

BASE_DIR="/opt/tixa"
STATE_DIR="/var/lib/tixa"
REGISTRY="$STATE_DIR/registry.json"

# shellcheck source=/opt/tixa/core/common.sh
source "$BASE_DIR/core/common.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Run this command as root: sudo tixa delete <project>"
  exit 1
fi

if [ -z "$PROJECT" ]; then
  echo "❌ Project name required"
  echo "👉 Usage: tixa delete <project>"
  exit 1
fi

PROJECT="${PROJECT,,}"

if [ ! -f "$REGISTRY" ]; then
  echo "❌ Registry not found"
  echo "👉 Cannot safely delete service"
  exit 1
fi

if ! jq -e --arg project "$PROJECT" '.[$project]' "$REGISTRY" >/dev/null; then
  echo "❌ Project '$PROJECT' not found"
  echo "👉 Run: tixa list"
  exit 1
fi

DOMAIN=$(jq -r --arg project "$PROJECT" '.[$project].domain' "$REGISTRY")
SERVICE_USER=$(jq -r --arg project "$PROJECT" '.[$project].service_user // ""' "$REGISTRY")
[ -n "$SERVICE_USER" ] || SERVICE_USER="$(tixa_service_user "$PROJECT")"

echo ""
echo "🗑️  TIXA · DELETE SERVICE"
echo "---------------------------"
echo "Project : $PROJECT"
echo "Domain  : $DOMAIN"
echo "---------------------------"

if [ "$MODE" != "--force" ]; then
  echo ""
  read -r -p "Type DELETE to confirm: " CONFIRM
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
if nginx -t >/dev/null 2>&1; then
  systemctl reload nginx
else
  echo "⚠️  Nginx configuration is invalid after removal; not reloading. Run: sudo nginx -t"
fi

echo "▶ Removing SSL certificate (if exists)"
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  certbot delete \
    --cert-name "$DOMAIN" \
    --non-interactive || true
fi

# The dedicated account exists only for this service, so it goes with it. Named
# accounts that predate per-service users (or a shared name) are left alone.
if [ "$SERVICE_USER" != "root" ] && [[ "$SERVICE_USER" == tixa-* ]] && id -u "$SERVICE_USER" >/dev/null 2>&1; then
  echo "▶ Removing service account: $SERVICE_USER"
  userdel "$SERVICE_USER" >/dev/null 2>&1 || true
  groupdel "$SERVICE_USER" >/dev/null 2>&1 || true
fi

echo "▶ Updating registry"
# Write through a temp file next to the registry. The previous fixed /tmp path
# let any local user pre-create a symlink and capture this root-owned write.
REGISTRY_CANDIDATE="$REGISTRY.delete-new"
jq --arg project "$PROJECT" 'del(.[$project])' "$REGISTRY" > "$REGISTRY_CANDIDATE"
tixa_commit_registry "$REGISTRY" "$REGISTRY_CANDIDATE"

echo ""
echo "✅ Service '$PROJECT' deleted completely"
echo "🧹 No residue left behind"
