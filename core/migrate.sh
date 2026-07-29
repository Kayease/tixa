#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="/opt/tixa"
STATE_DIR="/var/lib/tixa"
REGISTRY="$STATE_DIR/registry.json"
OLD_PROJECT="${1:-}"

# shellcheck source=/opt/tixa/core/common.sh
source "$BASE_DIR/core/common.sh"

fail() { echo "Error: $1"; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "run as root: sudo tixa migrate <service>"
bash "$BASE_DIR/core/doctor.sh" --quiet || fail "server preflight failed; run sudo tixa doctor"
[ -n "$OLD_PROJECT" ] || fail "usage: tixa migrate <current-service>"
OLD_PROJECT="${OLD_PROJECT,,}"
jq -e --arg project "$OLD_PROJECT" '.[$project]' "$REGISTRY" >/dev/null || fail "service '$OLD_PROJECT' not found"

REQUIREMENTS_FILE="$BASE_DIR/templates/service-requirements.txt"
[ -f "$REQUIREMENTS_FILE" ] || fail "missing $REQUIREMENTS_FILE; re-run the latest Tixa installer"

OLD_DOMAIN="$(jq -r --arg project "$OLD_PROJECT" '.[$project].domain' "$REGISTRY")"
PORT="$(jq -r --arg project "$OLD_PROJECT" '.[$project].port' "$REGISTRY")"
API_KEY="$(jq -r --arg project "$OLD_PROJECT" '.[$project].api_key' "$REGISTRY")"

echo ""
echo "TIXA SERVICE MIGRATION"
echo "Current project: $OLD_PROJECT"
echo "Current domain : $OLD_DOMAIN"
read -r -p "New project name: " NEW_PROJECT
read -r -p "New domain: " NEW_DOMAIN
NEW_PROJECT="${NEW_PROJECT,,}"
NEW_DOMAIN="${NEW_DOMAIN,,}"

[[ "$NEW_PROJECT" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || fail "invalid new project name"
[[ "$NEW_DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || fail "invalid public domain"
[[ "$NEW_DOMAIN" != *.local ]] || fail ".local domains cannot receive Let's Encrypt certificates"
[ "$NEW_PROJECT" != "$OLD_PROJECT" ] || fail "new project name must be different"
[ "$NEW_DOMAIN" != "$OLD_DOMAIN" ] || fail "new domain must be different"

jq -e --arg project "$NEW_PROJECT" '.[$project]' "$REGISTRY" >/dev/null && fail "service '$NEW_PROJECT' already exists"
jq -e --arg domain "$NEW_DOMAIN" '.[] | select(.domain == $domain)' "$REGISTRY" >/dev/null && fail "domain '$NEW_DOMAIN' is already registered"
[ ! -e "/opt/${NEW_PROJECT}-processor" ] || fail "/opt/${NEW_PROJECT}-processor already exists"
[ ! -e "/var/www/images/${NEW_PROJECT}" ] || fail "/var/www/images/${NEW_PROJECT} already exists"
[ ! -e "/etc/nginx/sites-available/${NEW_PROJECT}.conf" ] || fail "target Nginx configuration already exists"
[ ! -e "/etc/letsencrypt/live/${NEW_DOMAIN}" ] || fail "a local certificate already exists for '$NEW_DOMAIN'"

VPS_IP="$(curl -fs https://api.ipify.org)" || fail "unable to detect VPS public IP"
mapfile -t DOMAIN_IPS < <(dig +short A "$NEW_DOMAIN" | grep -E '^[0-9.]+$' || true)
[ "${#DOMAIN_IPS[@]}" -gt 0 ] || fail "no public DNS A record found for '$NEW_DOMAIN'"
printf '%s\n' "${DOMAIN_IPS[@]}" | grep -Fxq "$VPS_IP" || fail "'$NEW_DOMAIN' does not resolve to this VPS ($VPS_IP)"

echo ""
echo "Migration plan:"
echo "  $OLD_PROJECT ($OLD_DOMAIN)"
echo "  -> $NEW_PROJECT ($NEW_DOMAIN)"
echo "The API key and internal port will be preserved."
read -r -p "Type MIGRATE to continue: " CONFIRM
[ "$CONFIRM" = "MIGRATE" ] || fail "cancelled"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/var/backups/tixa-migrations/${TIMESTAMP}-${OLD_PROJECT}"
NEW_APP="/opt/${NEW_PROJECT}-processor"
OLD_APP="/opt/${OLD_PROJECT}-processor"
NEW_USER="$(tixa_service_user "$NEW_PROJECT")"
OLD_USER="$(tixa_service_user "$OLD_PROJECT")"

mkdir -p "$BACKUP_DIR"
cp "$REGISTRY" "$BACKUP_DIR/registry.json"
cp "/etc/systemd/system/${OLD_PROJECT}-processor.service" "$BACKUP_DIR/"
cp "/etc/nginx/sites-available/${OLD_PROJECT}.conf" "$BACKUP_DIR/"

NEW_NGINX=0
DATA_MOVED=0
OLD_STOPPED=0
NEW_USER_CREATED=0
OLD_UNIT_REMOVED=0
OLD_NGINX_REMOVED=0
OLD_APP_MOVED=0

rollback() {
  local exit_code=$?
  trap - ERR EXIT
  set +e  # a failure inside cleanup must not abandon the rest of it

  if [ "$exit_code" -eq 0 ]; then exit 0; fi

  echo "Migration failed; restoring the original service..."

  systemctl stop "${NEW_PROJECT}-processor" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/${NEW_PROJECT}-processor.service"

  if [ "$DATA_MOVED" -eq 1 ] && [ -d "/var/www/images/${NEW_PROJECT}" ]; then
    mv "/var/www/images/${NEW_PROJECT}" "/var/www/images/${OLD_PROJECT}"
  fi
  rm -rf "$NEW_APP"

  if [ "$NEW_NGINX" -eq 1 ]; then
    rm -f "/etc/nginx/sites-enabled/${NEW_PROJECT}.conf" "/etc/nginx/sites-available/${NEW_PROJECT}.conf"
  fi
  if [ "$NEW_USER_CREATED" -eq 1 ]; then
    userdel "$NEW_USER" >/dev/null 2>&1 || true
    groupdel "$NEW_USER" >/dev/null 2>&1 || true
  fi

  # Put the old runtime back. Without this the rollback could leave neither the
  # old nor the new service available.
  if [ "$OLD_APP_MOVED" -eq 1 ] && [ -d "$BACKUP_DIR/application" ]; then
    rm -rf "$OLD_APP"
    mv "$BACKUP_DIR/application" "$OLD_APP"
  fi
  if [ "$OLD_UNIT_REMOVED" -eq 1 ]; then
    cp -p "$BACKUP_DIR/${OLD_PROJECT}-processor.service" "/etc/systemd/system/"
  fi
  if [ "$OLD_NGINX_REMOVED" -eq 1 ]; then
    cp -p "$BACKUP_DIR/${OLD_PROJECT}.conf" "/etc/nginx/sites-available/"
    ln -sf "/etc/nginx/sites-available/${OLD_PROJECT}.conf" "/etc/nginx/sites-enabled/${OLD_PROJECT}.conf"
  fi

  cp "$BACKUP_DIR/registry.json" "$REGISTRY"
  chmod 600 "$REGISTRY"
  systemctl daemon-reload
  if [ "$OLD_STOPPED" -eq 1 ]; then systemctl enable --now "${OLD_PROJECT}-processor" >/dev/null 2>&1 || true; fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx || true

  echo "Original service restored. Backup retained at: $BACKUP_DIR"
  exit "$exit_code"
}
# EXIT as well as ERR: `fail` exits directly, which never raises ERR.
trap rollback ERR EXIT

echo "Preparing the new application runtime..."
if ! id -u "$NEW_USER" >/dev/null 2>&1; then NEW_USER_CREATED=1; fi
tixa_ensure_service_user "$NEW_USER"

python3 -m venv "$NEW_APP/venv"
"$NEW_APP/venv/bin/pip" install --quiet --upgrade pip
"$NEW_APP/venv/bin/pip" install --quiet -r "$REQUIREMENTS_FILE"
sed -e "s/{{PROJECT}}/${NEW_PROJECT}/g" -e "s|{{API_KEY}}|${API_KEY}|g" -e "s|{{BASE_URL}}|https://${NEW_DOMAIN}|g" \
  "$BASE_DIR/templates/main.py" > "$NEW_APP/main.py"
"$NEW_APP/venv/bin/python" -m py_compile "$NEW_APP/main.py"

tixa_install_nginx_limits "$BASE_DIR"
sed -e "s/{{PROJECT}}/${NEW_PROJECT}/g" -e "s/{{DOMAIN}}/${NEW_DOMAIN}/g" -e "s/{{PORT}}/${PORT}/g" \
  "$BASE_DIR/templates/nginx.conf.tpl" > "/etc/nginx/sites-available/${NEW_PROJECT}.conf"
ln -s "/etc/nginx/sites-available/${NEW_PROJECT}.conf" "/etc/nginx/sites-enabled/${NEW_PROJECT}.conf"
NEW_NGINX=1
nginx -t
systemctl reload nginx

echo "Issuing the certificate for $NEW_DOMAIN before cutover..."
certbot --nginx -d "$NEW_DOMAIN" --agree-tos --non-interactive -m "$(cat "$STATE_DIR/sslemail")"

systemctl stop "${OLD_PROJECT}-processor"
systemctl disable "${OLD_PROJECT}-processor" >/dev/null
OLD_STOPPED=1
mv "/var/www/images/${OLD_PROJECT}" "/var/www/images/${NEW_PROJECT}"
DATA_MOVED=1

sed -e "s/{{PROJECT}}/${NEW_PROJECT}/g" -e "s/{{PORT}}/${PORT}/g" -e "s/{{SERVICE_USER}}/${NEW_USER}/g" \
  "$BASE_DIR/templates/service.tpl" > "/etc/systemd/system/${NEW_PROJECT}-processor.service"
tixa_apply_ownership "$NEW_PROJECT" "$NEW_USER"
systemctl daemon-reload
systemctl enable --now "${NEW_PROJECT}-processor"
tixa_wait_for_health "$NEW_PROJECT" "$PORT" || fail "the migrated service did not report healthy"

REGISTRY_CANDIDATE="$REGISTRY.migrate-new"
jq --arg old "$OLD_PROJECT" --arg new "$NEW_PROJECT" --arg domain "$NEW_DOMAIN" --arg user "$NEW_USER" \
  '.[$new] = (.[$old] | .domain = $domain | .ssl = "installed" | .service_user = $user) | del(.[$old])' \
  "$REGISTRY" > "$REGISTRY_CANDIDATE"
tixa_commit_registry "$REGISTRY" "$REGISTRY_CANDIDATE"

# ---------------------------------------------------------------
# Commit stage. Every check that can still fail runs before the old
# runtime is moved out of the way, so a late failure can always put
# the original service back.
# ---------------------------------------------------------------
rm -f "/etc/systemd/system/${OLD_PROJECT}-processor.service"
OLD_UNIT_REMOVED=1
rm -f "/etc/nginx/sites-enabled/${OLD_PROJECT}.conf" "/etc/nginx/sites-available/${OLD_PROJECT}.conf"
OLD_NGINX_REMOVED=1
systemctl daemon-reload
nginx -t
systemctl reload nginx

mv "$OLD_APP" "$BACKUP_DIR/application"
OLD_APP_MOVED=1

trap - ERR EXIT

# The old service account is no longer referenced by any unit.
if [ "$OLD_USER" != "$NEW_USER" ] && id -u "$OLD_USER" >/dev/null 2>&1; then
  userdel "$OLD_USER" >/dev/null 2>&1 || true
  groupdel "$OLD_USER" >/dev/null 2>&1 || true
fi

echo "Migration completed successfully"
echo "New service : $NEW_PROJECT"
echo "New URL     : https://$NEW_DOMAIN"
echo "Service user: $NEW_USER"
echo "Backup      : $BACKUP_DIR"
echo "The old certificate was retained for rollback and can be removed later with Certbot."
