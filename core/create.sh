#!/usr/bin/env bash
set -e

BASE_DIR="/opt/tixa"
REGISTRY="$BASE_DIR/registry/services.json"

validate_domain() {
  local domain="$1"

  echo "▶ Validating domain: $domain"

  VPS_IP=$(curl -s https://api.ipify.org)

  if [ -z "$VPS_IP" ]; then
    echo "❌ Unable to detect VPS public IP"
    exit 1
  fi

  DOMAIN_IP=$(dig +short "$domain" | grep -E '^[0-9.]+' | head -n 1)

  if [ -z "$DOMAIN_IP" ]; then
    echo ""
    echo "❌ Domain validation failed"
    echo ""
    echo "Domain: $domain"
    echo "Reason: DNS record not found (NXDOMAIN)"
    echo ""
    echo "👉 Fix:"
    echo "Add an A record in your DNS:"
    echo "$domain → $VPS_IP"
    echo ""
    echo "Wait for DNS propagation, then run:"
    echo "tixa create"
    echo ""
    exit 1
  fi

  if [ "$DOMAIN_IP" != "$VPS_IP" ]; then
    echo ""
    echo "❌ Domain validation failed"
    echo ""
    echo "Domain      : $domain"
    echo "Resolved IP : $DOMAIN_IP"
    echo "Your VPS IP : $VPS_IP"
    echo ""
    echo "👉 Fix:"
    echo "Update DNS A record to point to this VPS:"
    echo "$domain → $VPS_IP"
    echo ""
    echo "Then re-run:"
    echo "tixa create"
    echo ""
    exit 1
  fi

  echo "✅ Domain validated successfully"
  echo "$domain → $VPS_IP"
  echo ""
}


echo ""
echo "🧩 TIXA · CREATE MEDIA SERVICE"
echo ""

read -p "Project name: " PROJECT
read -p "Domain (e.g. img.example.com): " DOMAIN

validate_domain "$DOMAIN"

API_KEY="${PROJECT,,}_live_$(openssl rand -hex 16)"

PORT=$(shuf -i 10000-19999 -n 1)
echo "▶ Selected free port: $PORT"
echo ""
echo "Configuration summary:"
echo "--------------------------------"
echo "Project : $PROJECT"
echo "Domain  : $DOMAIN"
echo "Port    : $PORT"
echo "API Key : $API_KEY"
echo "--------------------------------"
echo ""
read -p "Type CREATE to continue: " CONFIRM

if [ "$CONFIRM" != "CREATE" ]; then
  echo "❌ Cancelled"
  exit 1
fi

echo "▶ Creating directories"
mkdir -p /opt/${PROJECT}-processor
mkdir -p /var/www/images/$PROJECT/{originals,cache,thumbnails}

echo "▶ Setting up Python app"
python3 -m venv /opt/${PROJECT}-processor/venv
source /opt/${PROJECT}-processor/venv/bin/activate
pip install --upgrade pip
pip install fastapi uvicorn python-multipart pyvips pillow pymupdf python-magic aiofiles
deactivate

sed \
  -e "s/{{PROJECT}}/$PROJECT/g" \
  -e "s/{{API_KEY}}/$API_KEY/g" \
  -e "s|{{BASE_URL}}|https://$DOMAIN|g" \
  $BASE_DIR/templates/main.py \
  > /opt/${PROJECT}-processor/main.py

echo "▶ Creating systemd service"
sed \
  -e "s/{{PROJECT}}/$PROJECT/g" \
  -e "s/{{PORT}}/$PORT/g" \
  $BASE_DIR/templates/service.tpl \
  > /etc/systemd/system/${PROJECT}-processor.service

systemctl daemon-reload
systemctl enable ${PROJECT}-processor
systemctl start ${PROJECT}-processor

echo "▶ Creating nginx config"
sed \
  -e "s/{{PROJECT}}/$PROJECT/g" \
  -e "s/{{DOMAIN}}/$DOMAIN/g" \
  -e "s/{{PORT}}/$PORT/g" \
  $BASE_DIR/templates/nginx.conf.tpl \
  > /etc/nginx/sites-available/${PROJECT}.conf

ln -sf /etc/nginx/sites-available/${PROJECT}.conf /etc/nginx/sites-enabled/${PROJECT}.conf
nginx -t
systemctl reload nginx

echo ""
echo "▶ Installing SSL certificate for $DOMAIN"

CERTBOT_EMAIL_FILE="/opt/tixa/.certbot_email"

if [ ! -f "$CERTBOT_EMAIL_FILE" ]; then
  echo "❌ Certbot email not found. Run install.sh again."
  exit 1
fi

certbot --nginx \
  -d "$DOMAIN" \
  --agree-tos \
  --non-interactive \
  -m "$(cat $CERTBOT_EMAIL_FILE)" \
  || {
    echo ""
    echo "❌ SSL certificate installation failed"
    echo ""
    echo "👉 Try running manually:"
    echo "certbot --nginx -d $DOMAIN"
    echo ""
    exit 1
  }

echo "✅ SSL certificate installed successfully"

systemctl reload nginx


jq ". + {
  \"$PROJECT\": {
    \"domain\": \"$DOMAIN\",
    \"port\": $PORT,
    \"api_key\": \"$API_KEY\"
  }
}" "$REGISTRY" > /tmp/services.json && mv /tmp/services.json "$REGISTRY"


echo "✅ Service created successfully"
echo ""
echo "🎉 SERVICE CREATED SUCCESSFULLY"
echo "----------------------------------------"
echo "Project Name : $PROJECT"
echo "Domain       : https://$DOMAIN"
echo "Health Check : https://$DOMAIN/health"
echo "Internal URL : http://127.0.0.1:$PORT"
echo "API Key      : $API_KEY"
echo ""
echo "📌 Save this API key securely."
echo "----------------------------------------"
