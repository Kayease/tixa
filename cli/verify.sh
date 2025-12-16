#!/usr/bin/env bash
set -e

PROJECT="$1"

STATE_DIR="/var/lib/tixa"
REGISTRY="$STATE_DIR/registry.json"

if [ -z "$PROJECT" ]; then
  echo "❌ Usage: tixa verify <project>"
  exit 1
fi

if [ ! -f "$REGISTRY" ]; then
  echo "❌ Registry not found"
  echo "👉 No services registered"
  exit 1
fi

if ! jq -e ".\"$PROJECT\"" "$REGISTRY" >/dev/null; then
  echo "❌ Project '$PROJECT' not found"
  echo "👉 Run: tixa list"
  exit 1
fi

DOMAIN=$(jq -r ".\"$PROJECT\".domain" "$REGISTRY")
PORT=$(jq -r ".\"$PROJECT\".port" "$REGISTRY")
SERVICE="${PROJECT}-processor"

echo ""
echo "🔍 TIXA · VERIFY SERVICE"
echo "---------------------------"
echo "Project : $PROJECT"
echo "Domain  : $DOMAIN"
echo "Port    : $PORT"
echo "---------------------------"

# systemd
if systemctl is-active --quiet "$SERVICE"; then
  echo "✅ systemd service is running"
else
  echo "❌ systemd service NOT running"
fi

# port
if ss -lnt | grep -q ":$PORT"; then
  echo "✅ port $PORT is listening"
else
  echo "❌ port $PORT is NOT listening"
fi

# nginx
if [ -f "/etc/nginx/sites-available/$PROJECT.conf" ]; then
  echo "✅ nginx config exists"
else
  echo "❌ nginx config missing"
fi

if [ -L "/etc/nginx/sites-enabled/$PROJECT.conf" ]; then
  echo "✅ nginx config is enabled"
else
  echo "❌ nginx config NOT enabled"
fi

# internal health
if curl -fs "http://127.0.0.1:$PORT/health" >/dev/null; then
  echo "✅ internal /health OK"
else
  echo "❌ internal /health FAILED"
fi

echo "---------------------------"
echo "🌐 Public URL: https://$DOMAIN/health"
