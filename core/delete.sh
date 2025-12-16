#!/usr/bin/env bash
set -e

PROJECT="$1"
REGISTRY="/opt/tixa/registry/services.json"

if [ -z "$PROJECT" ]; then
  echo "❌ Project name required"
  exit 1
fi

echo "▶ Removing service $PROJECT"

systemctl stop ${PROJECT}-processor || true
systemctl disable ${PROJECT}-processor || true
rm -f /etc/systemd/system/${PROJECT}-processor.service
systemctl daemon-reload

rm -rf /opt/${PROJECT}-processor
rm -rf /var/www/images/$PROJECT
rm -f /etc/nginx/sites-enabled/${PROJECT}.conf
rm -f /etc/nginx/sites-available/${PROJECT}.conf
systemctl reload nginx

jq "del(.\"$PROJECT\")" $REGISTRY > /tmp/services.json && mv /tmp/services.json $REGISTRY

echo "✅ Service deleted completely"
