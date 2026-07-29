#!/usr/bin/env bash
set -Eeuo pipefail

# -------------------------------------------------
# Paths (DO NOT CHANGE)
# -------------------------------------------------
BASE_DIR="/opt/tixa"
STATE_DIR="/var/lib/tixa"

REGISTRY="$STATE_DIR/registry.json"
SSL_EMAIL_FILE="$STATE_DIR/sslemail"

# shellcheck source=/opt/tixa/core/common.sh
source "$BASE_DIR/core/common.sh"

# -------------------------------------------------
# Helpers
# -------------------------------------------------
fail() {
  echo ""
  echo "❌ $1"
  echo ""
  exit 1
}

if [ "$(id -u)" -ne 0 ]; then
  fail "Run this command as root: sudo tixa create"
fi

bash "$BASE_DIR/core/doctor.sh" --quiet || \
  fail "Server compatibility check failed. Run: sudo tixa doctor"

for COMMAND in jq curl dig openssl python3 nginx certbot systemctl ss useradd; do
  command -v "$COMMAND" >/dev/null 2>&1 || \
    fail "Missing required command '$COMMAND'. Re-run the latest Tixa installer."
done

python3 -m venv --help >/dev/null 2>&1 || \
  fail "Python venv support is missing. Re-run the latest Tixa installer."

REQUIREMENTS_FILE="$BASE_DIR/templates/service-requirements.txt"
[ -f "$REQUIREMENTS_FILE" ] || fail "Missing $REQUIREMENTS_FILE. Re-run the latest Tixa installer."

# -------------------------------------------------
# Startup checks
# -------------------------------------------------
mkdir -p "$STATE_DIR"

if [ ! -f "$REGISTRY" ]; then
  echo "{}" > "$REGISTRY"
  chmod 600 "$REGISTRY"
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

read -r -p "Project name: " PROJECT
read -r -p "Domain (e.g. img.example.com): " DOMAIN

[ -z "$PROJECT" ] && fail "Project name cannot be empty"
[ -z "$DOMAIN" ] && fail "Domain cannot be empty"

PROJECT_LOWER="${PROJECT,,}"

if [[ ! "$PROJECT_LOWER" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; then
  fail "Project name must contain only letters, numbers, and hyphens (maximum 63 characters)"
fi

DOMAIN="${DOMAIN,,}"
if [[ ! "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]; then
  fail "Enter a valid public domain name"
fi

if [[ "$DOMAIN" == *.local ]]; then
  fail ".local domains cannot receive public Let's Encrypt certificates. Use a real public domain."
fi

if nginx -T 2>&1 | grep -E "server_name[[:space:]].*\b${DOMAIN//./\.}\b" >/dev/null; then
  fail "Domain '$DOMAIN' already exists in an Nginx configuration"
fi

if [ -e "/etc/letsencrypt/live/$DOMAIN" ]; then
  fail "A locally managed certificate already exists for '$DOMAIN'; resolve it before Tixa takes ownership"
fi

# -------------------------------------------------
# Registry validation
# -------------------------------------------------
if jq -e --arg project "$PROJECT_LOWER" '.[$project]' "$REGISTRY" >/dev/null; then
  fail "Project '$PROJECT_LOWER' already exists"
fi

if jq -e --arg domain "$DOMAIN" '.[] | select(.domain == $domain)' "$REGISTRY" >/dev/null; then
  fail "Domain '$DOMAIN' is already linked to another service"
fi

# A previous run that failed part-way leaves these behind. Refuse rather than
# writing over somebody else's data.
for LEFTOVER in "/opt/${PROJECT_LOWER}-processor" "/var/www/images/${PROJECT_LOWER}" \
                "/etc/nginx/sites-available/${PROJECT_LOWER}.conf" \
                "/etc/systemd/system/${PROJECT_LOWER}-processor.service"; do
  if [ -e "$LEFTOVER" ]; then
    fail "'$LEFTOVER' already exists but '$PROJECT_LOWER' is not registered. Remove it, then retry."
  fi
done

# -------------------------------------------------
# Domain → VPS validation
# -------------------------------------------------
echo ""
echo "▶ Validating domain: $DOMAIN"

VPS_IP=$(curl -fs https://api.ipify.org) || fail "Unable to detect VPS public IP"

mapfile -t DOMAIN_IPS < <(dig +short A "$DOMAIN" | grep -E '^[0-9.]+$' || true)

if [ "${#DOMAIN_IPS[@]}" -eq 0 ]; then
  echo ""
  echo "❌ Domain validation failed"
  echo "Reason : DNS record not found"
  echo ""
  echo "👉 Add A record:"
  echo "$DOMAIN → $VPS_IP"
  echo ""
  exit 1
fi

if ! printf '%s\n' "${DOMAIN_IPS[@]}" | grep -Fxq "$VPS_IP"; then
  echo ""
  echo "❌ Domain validation failed"
  echo "Domain IP : ${DOMAIN_IPS[0]}"
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

# Pick a port that is actually free. Choosing at random without checking meant
# creation could silently collide with a listener already on that port.
PORT="$(tixa_find_available_port "$REGISTRY")" || \
  fail "Could not find a free port in 10000-19999. Free one and retry."

SERVICE_USER="$(tixa_service_user "$PROJECT_LOWER")"

echo ""
echo "Configuration summary:"
echo "--------------------------------"
echo "Project      : $PROJECT_LOWER"
echo "Domain       : $DOMAIN"
echo "Port         : $PORT (127.0.0.1 only)"
echo "Service user : $SERVICE_USER"
echo "API Key      : $API_KEY"
echo "--------------------------------"
echo ""

read -r -p "Type CREATE to continue: " CONFIRM
[ "$CONFIRM" != "CREATE" ] && fail "Cancelled"

# -------------------------------------------------
# Rollback
#
# Everything past this point mutates the server. Track each resource so a
# failure removes exactly what this run created and nothing else.
# -------------------------------------------------
CREATED_APP=0
CREATED_MEDIA=0
CREATED_USER=0
CREATED_UNIT=0
CREATED_NGINX=0
CREATED_CERT=0
COMMITTED=0

rollback() {
  local exit_code=$?
  trap - ERR EXIT
  set +e  # a failure inside cleanup must not abandon the rest of it

  if [ "$COMMITTED" -eq 1 ] || [ "$exit_code" -eq 0 ]; then
    exit "$exit_code"
  fi

  echo ""
  echo "⚠️  Creation failed; removing what this run created..."

  if [ "$CREATED_UNIT" -eq 1 ]; then
    systemctl stop "${PROJECT_LOWER}-processor" >/dev/null 2>&1 || true
    systemctl disable "${PROJECT_LOWER}-processor" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${PROJECT_LOWER}-processor.service"
    systemctl daemon-reload || true
  fi
  if [ "$CREATED_CERT" -eq 1 ]; then
    certbot delete --cert-name "$DOMAIN" --non-interactive >/dev/null 2>&1 || true
  fi
  if [ "$CREATED_NGINX" -eq 1 ]; then
    rm -f "/etc/nginx/sites-enabled/${PROJECT_LOWER}.conf" \
          "/etc/nginx/sites-available/${PROJECT_LOWER}.conf"
    if nginx -t >/dev/null 2>&1; then systemctl reload nginx || true; fi
  fi
  [ "$CREATED_APP" -eq 1 ] && rm -rf "/opt/${PROJECT_LOWER}-processor"
  [ "$CREATED_MEDIA" -eq 1 ] && rm -rf "/var/www/images/${PROJECT_LOWER}"
  if [ "$CREATED_USER" -eq 1 ]; then
    userdel "$SERVICE_USER" >/dev/null 2>&1 || true
    groupdel "$SERVICE_USER" >/dev/null 2>&1 || true
  fi

  echo "Rollback complete. The server is back to its previous state."
  exit "$exit_code"
}
# EXIT as well as ERR: `fail` exits directly, which never raises ERR.
trap rollback ERR EXIT

# -------------------------------------------------
# Service account
# -------------------------------------------------
echo "▶ Creating service account"

if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  CREATED_USER=1
fi
tixa_ensure_service_user "$SERVICE_USER"

# -------------------------------------------------
# Filesystem
# -------------------------------------------------
echo "▶ Creating directories"

mkdir -p "/opt/${PROJECT_LOWER}-processor"
CREATED_APP=1
mkdir -p "/var/www/images/${PROJECT_LOWER}"/{originals,cache,thumbnails}
CREATED_MEDIA=1

# -------------------------------------------------
# Python app
# -------------------------------------------------
echo "▶ Setting up Python app"

python3 -m venv "/opt/${PROJECT_LOWER}-processor/venv"
"/opt/${PROJECT_LOWER}-processor/venv/bin/pip" install --quiet --upgrade pip
"/opt/${PROJECT_LOWER}-processor/venv/bin/pip" install --quiet -r "$REQUIREMENTS_FILE"

sed \
  -e "s/{{PROJECT}}/${PROJECT_LOWER}/g" \
  -e "s/{{API_KEY}}/${API_KEY}/g" \
  -e "s|{{BASE_URL}}|https://${DOMAIN}|g" \
  "$BASE_DIR/templates/main.py" \
  > "/opt/${PROJECT_LOWER}-processor/main.py"

# Validate before anything is started, so a broken template never reaches systemd.
"/opt/${PROJECT_LOWER}-processor/venv/bin/python" -m py_compile \
  "/opt/${PROJECT_LOWER}-processor/main.py"

tixa_apply_ownership "$PROJECT_LOWER" "$SERVICE_USER"

# -------------------------------------------------
# systemd
# -------------------------------------------------
echo "▶ Creating systemd service"

sed \
  -e "s/{{PROJECT}}/${PROJECT_LOWER}/g" \
  -e "s/{{PORT}}/${PORT}/g" \
  -e "s/{{SERVICE_USER}}/${SERVICE_USER}/g" \
  "$BASE_DIR/templates/service.tpl" \
  > "/etc/systemd/system/${PROJECT_LOWER}-processor.service"
CREATED_UNIT=1

systemctl daemon-reload
systemctl enable "${PROJECT_LOWER}-processor"
systemctl start "${PROJECT_LOWER}-processor"

echo "▶ Waiting for the service to report healthy"
tixa_wait_for_health "$PROJECT_LOWER" "$PORT" || \
  fail "Service did not become healthy. Inspect: journalctl -u ${PROJECT_LOWER}-processor -n 50"

# -------------------------------------------------
# Nginx
# -------------------------------------------------
echo "▶ Creating nginx config"

tixa_install_nginx_limits "$BASE_DIR"

sed \
  -e "s/{{PROJECT}}/${PROJECT_LOWER}/g" \
  -e "s/{{DOMAIN}}/${DOMAIN}/g" \
  -e "s/{{PORT}}/${PORT}/g" \
  "$BASE_DIR/templates/nginx.conf.tpl" \
  > "/etc/nginx/sites-available/${PROJECT_LOWER}.conf"

ln -sf "/etc/nginx/sites-available/${PROJECT_LOWER}.conf" \
       "/etc/nginx/sites-enabled/${PROJECT_LOWER}.conf"
CREATED_NGINX=1

nginx -t
systemctl reload nginx

# -------------------------------------------------
# SSL
# -------------------------------------------------
echo ""
echo "▶ Installing SSL certificate for $DOMAIN"

SSL_STATUS="installed"
CERTBOT_LOG="$(mktemp /tmp/tixa-certbot.XXXXXX)"

if certbot --nginx \
  -d "$DOMAIN" \
  --agree-tos \
  --non-interactive \
  -m "$(cat "$SSL_EMAIL_FILE")" >"$CERTBOT_LOG" 2>&1; then
  CREATED_CERT=1
  echo "✅ SSL certificate installed"
else
  SSL_STATUS="pending"
  echo ""
  echo "⚠️  SSL certificate was NOT installed"
  echo "Reason:"
  tixa_describe_certbot_failure "$CERTBOT_LOG" | sed 's/^/• /'
  echo ""
  echo "👉 Your service is live on HTTP and will work normally."
  echo "⏳ Retry SSL with:"
  echo "tixa ssl renew ${PROJECT_LOWER}"
  echo ""
fi
rm -f "$CERTBOT_LOG"

nginx -t
systemctl reload nginx

# -------------------------------------------------
# Registry update (LAST STEP)
# -------------------------------------------------
REGISTRY_CANDIDATE="$REGISTRY.create-new"

jq --arg project "$PROJECT_LOWER" \
   --arg domain "$DOMAIN" \
   --argjson port "$PORT" \
   --arg key "$API_KEY" \
   --arg ssl "$SSL_STATUS" \
   --arg user "$SERVICE_USER" \
   '.[$project] = {domain: $domain, port: $port, api_key: $key, ssl: $ssl, service_user: $user}' \
   "$REGISTRY" > "$REGISTRY_CANDIDATE"

tixa_commit_registry "$REGISTRY" "$REGISTRY_CANDIDATE"
COMMITTED=1
trap - ERR EXIT

# -------------------------------------------------
# Success
# -------------------------------------------------
SCHEME="https"
[ "$SSL_STATUS" = "installed" ] || SCHEME="http"

echo ""
echo "🎉 SERVICE CREATED SUCCESSFULLY"
echo "----------------------------------------"
echo "Project Name : $PROJECT_LOWER"
echo "Domain       : ${SCHEME}://${DOMAIN}"
echo "Health Check : ${SCHEME}://${DOMAIN}/health"
echo "API Docs     : ${SCHEME}://${DOMAIN}/docs"
echo "Internal URL : http://127.0.0.1:${PORT}"
echo "Service User : $SERVICE_USER"
echo "SSL          : $SSL_STATUS"
echo "API Key      : ${API_KEY}"
echo "----------------------------------------"
echo "📌 Save this API key securely."
echo ""
