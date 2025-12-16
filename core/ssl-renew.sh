#!/usr/bin/env bash
set -e

REGISTRY="/opt/tixa/registry/services.json"

renew_one() {
  local PROJECT="$1"
  local DOMAIN

  DOMAIN=$(jq -r ".\"$PROJECT\".domain" "$REGISTRY")

  if [ "$DOMAIN" == "null" ]; then
    echo "❌ Project '$PROJECT' not found"
    exit 1
  fi

  echo ""
  echo "🔐 Renewing SSL for: $PROJECT"
  echo "Domain: $DOMAIN"

  if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    echo "❌ No SSL certificate found for $DOMAIN"
    echo "👉 Run: tixa create $PROJECT"
    exit 1
  fi

  certbot renew --cert-name "$DOMAIN" --quiet

  echo "✅ SSL renewed (if required) for $DOMAIN"
}

echo ""
echo "🔁 TIXA · SSL RENEW"
echo "---------------------------"

if [ "$1" == "all" ]; then
  jq -r 'keys[]' "$REGISTRY" | while read -r PROJECT; do
    renew_one "$PROJECT"
  done
else
  renew_one "$1"
fi

systemctl reload nginx
echo ""
echo "🌐 Nginx reloaded"
echo "✅ SSL renew completed"

