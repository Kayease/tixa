#!/usr/bin/env bash
set -e

# -------------------------------------------------
# Paths (DO NOT CHANGE)
# -------------------------------------------------
BASE_DIR="/opt/tixa"
STATE_DIR="/var/lib/tixa"

REGISTRY="$STATE_DIR/registry.json"
SSL_EMAIL_FILE="$STATE_DIR/sslemail"

# -------------------------------------------------
# Helpers
# -------------------------------------------------
fail() {
  echo ""
  echo "❌ $1"
  echo ""
  exit 1
}

# -------------------------------------------------
# Startup checks
# -------------------------------------------------
mkdir -p "$STATE_DIR"

if [ ! -f "$REGISTRY" ]; then
  echo "{}" > "$REGISTRY"
fi

if [ ! -f "$SSL_EMAIL_FILE" ]; then
  fail "SSL email not configured. Run: tixa sslemail set"
fi

# -------------------------------------------------
# UI
# -------------------------------------------------
echo ""
echo "🧩 TIXA · CREATE MEDIA SERVICE"
echo ""

read -p "Project name: " PROJECT
read -p "Domain (e.g. img.example.com): " DOMAIN

[ -z "$PROJECT" ] && fail "Project name cannot be empty"
[ -z "$DOMAIN" ] && fail "Domain cannot be empty"

PROJECT_LOWER="${PROJECT,,}"

# -------------------------------------------------
# Registry validation
# -------------------------------------------------
if jq -e ".\"$PROJECT_LOWER\"" "$REGISTRY" >/dev/null; then
  fail "Project '$PROJECT_LOWER' already exists"
fi

if jq -e ".[] | select(.domain == \"$DOMAIN\")" "$REGISTRY" >/dev/null; then
  fail "Domain '$DOMAIN' already linked to another service"
fi

# -------------------------------------------------
# Domain → VPS validation
# -------------------------------------------------
echo ""
echo "▶ Validating domain: $DOMAIN"

VPS_IP=$(curl -s https://api.ipify.org)
[ -z "$VPS_IP" ] && fail "Unable to detect VPS public IP"

DOMAIN_IP=$(dig +short "$DOMAIN" | grep -E '^[0-9.]+' | head -n 1)

if [ -z "$DOMAIN_IP" ]; then
  echo ""
  echo "❌ Domain validation failed"
  echo "Reason : DNS record not found"
  echo ""
  echo "👉 Add A record:"
  echo "$DOMAIN → $VPS_IP"
  echo ""
  exit 1
fi

if [ "$DOMAIN_IP" != "$VPS_IP" ]; then
  echo ""
  echo "❌ Domain validation failed"
  echo "Domain IP : $DOMAIN_IP"
  echo "VPS IP    : $VPS_IP"
  echo ""
  echo "👉 Fix DNS A record:"
  echo "$DOMAIN → $VPS_IP"
  echo ""
  exit 1
fi

echo "✅ Domain validated successfully"
echo "$DOMAIN → $VPS_IP"

# -------------------------------------------------
# Generate credentials
# -------------------------------------------------
API_KEY="${PROJECT_LOWER}_live_$(openssl rand -hex 16)"
PORT=$(shuf -i 10000-19999 -n 1)

echo ""
echo "Configuration summary:"
echo "--------------------------------"
echo "Project : $PROJECT_LOWER"
echo "Domain  : $DOMAIN"
echo "Port    : $PORT"
echo "API Key : $API_KEY"
echo "--------------------------------"
echo ""

read -p "Type CREATE to continue: " CONFIRM
[ "$CONFIRM" != "CREATE" ] && fail "Cancelled"

# -------------------------------------------------
# Filesystem
# -------------------------------------------------
echo "▶ Creating directories"

mkdir -p "/opt/${PROJECT_LOWER}-processor"
mkdir -p "/var/www/images/${PROJECT_LOWER}"/{originals,cache,thumbnails}

# -------------------------------------------------
# Python app
# -------------------------------------------------
echo "▶ Setting up Python app"

python3 -m venv "/opt/${PROJECT_LOWER}-processor/venv"
source "/opt/${PROJECT_LOWER}-processor/venv/bin/activate"

pip install --upgrade pip
pip install fastapi uvicorn python-multipart pyvips pillow pymupdf python-magic aiofiles

deactivate

sed \
  -e "s/{{PROJECT}}/${PROJECT_LOWER}/g" \
  -e "s/{{API_KEY}}/${API_KEY}/g" \
  -e "s|{{BASE_URL}}|https://${DOMAIN}|g" \
  "$BASE_DIR/templates/main.py" \
  > "/opt/${PROJECT_LOWER}-processor/main.py"

# -------------------------------------------------
# systemd
# -------------------------------------------------
echo "▶ Creating systemd service"

sed \
  -e "s/{{PROJECT}}/${PROJECT_LOWER}/g" \
  -e "s/{{PORT}}/${PORT}/g" \
  "$BASE_DIR/templates/service.tpl" \
  > "/etc/systemd/system/${PROJECT_LOWER}-processor.service"

systemctl daemon-reload
systemctl enable "${PROJECT_LOWER}-processor"
systemctl start "${PROJECT_LOWER}-processor"

# -------------------------------------------------
# Nginx
# -------------------------------------------------
echo "▶ Creating nginx config"

sed \
  -e "s/{{PROJECT}}/${PROJECT_LOWER}/g" \
  -e "s/{{DOMAIN}}/${DOMAIN}/g" \
  -e "s/{{PORT}}/${PORT}/g" \
  "$BASE_DIR/templates/nginx.conf.tpl" \
  > "/etc/nginx/sites-available/${PROJECT_LOWER}.conf"

ln -sf "/etc/nginx/sites-available/${PROJECT_LOWER}.conf" \
       "/etc/nginx/sites-enabled/${PROJECT_LOWER}.conf"

nginx -t
systemctl reload nginx

# -------------------------------------------------
# SSL
# -------------------------------------------------
echo ""
echo "▶ Installing SSL certificate for $DOMAIN"

certbot --nginx \
  -d "$DOMAIN" \
  --agree-tos \
  --non-interactive \
  -m "$(cat "$SSL_EMAIL_FILE")" \
  || fail "SSL certificate installation failed"

systemctl reload nginx
echo "✅ SSL certificate installed"

# -------------------------------------------------
# Registry update (LAST STEP)
# -------------------------------------------------
jq ". + {
  \"${PROJECT_LOWER}\": {
    \"domain\": \"${DOMAIN}\",
    \"port\": ${PORT},
    \"api_key\": \"${API_KEY}\"
  }
}" "$REGISTRY" > /tmp/tixa-registry.json \
  && mv /tmp/tixa-registry.json "$REGISTRY"

# -------------------------------------------------
# Success
# -------------------------------------------------
echo ""
echo "🎉 SERVICE CREATED SUCCESSFULLY"
echo "----------------------------------------"
echo "Project Name : $PROJECT_LOWER"
echo "Domain       : https://${DOMAIN}"
echo "Health Check : https://${DOMAIN}/health"
echo "Internal URL : http://127.0.0.1:${PORT}"
echo "API Key      : ${API_KEY}"
echo "----------------------------------------"
echo "📌 Save this API key securely."
echo ""
