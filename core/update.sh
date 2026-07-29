#!/usr/bin/env bash
set -Eeuo pipefail

# -------------------------------------------------
# TIXA UPDATE - Safely update running services
# -------------------------------------------------

BASE_DIR="/opt/tixa"
STATE_DIR="/var/lib/tixa"
REGISTRY="$STATE_DIR/registry.json"
BACKUP_DIR="/var/backups/tixa-updates"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# shellcheck source=/opt/tixa/core/common.sh
source "$BASE_DIR/core/common.sh"

# -------------------------------------------------
# Colors
# -------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------------------------------------------------
# Helpers
# -------------------------------------------------
log_info()    { echo -e "${BLUE}▶${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error()   { echo -e "${RED}✗${NC} $1"; }

fail() {
  echo ""
  log_error "$1"
  echo ""
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "Run this command as root: sudo tixa update"

# -------------------------------------------------
# Startup checks
# -------------------------------------------------
if [ ! -f "$REGISTRY" ]; then
  fail "No services found. Registry file does not exist."
fi

REQUIREMENTS_FILE="$BASE_DIR/templates/service-requirements.txt"
if [ ! -f "$BASE_DIR/templates/main.py" ]; then
  fail "Template file not found: $BASE_DIR/templates/main.py"
fi
[ -f "$REQUIREMENTS_FILE" ] || fail "Template file not found: $REQUIREMENTS_FILE"

mkdir -p "$BACKUP_DIR"

# -------------------------------------------------
# Parse arguments
# -------------------------------------------------
TARGET_SERVICE=""
SKIP_BACKUP=""
AUTO_YES=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-backup) SKIP_BACKUP="yes"; shift ;;
    --yes|-y)      AUTO_YES="yes"; shift ;;
    --all)         TARGET_SERVICE="--all"; shift ;;
    *)
      # Only the first non-flag argument names a service. Seeding this from $1
      # before the loop made `tixa update --yes` look for a service named
      # "--yes".
      if [ -z "$TARGET_SERVICE" ]; then TARGET_SERVICE="$1"; fi
      shift
      ;;
  esac
done

# -------------------------------------------------
# UI
# -------------------------------------------------
echo ""
echo "🔄 TIXA · UPDATE SERVICES"
echo ""

# -------------------------------------------------
# Get list of services to update
# -------------------------------------------------
if [ "$TARGET_SERVICE" == "--all" ]; then
  mapfile -t SERVICE_LIST < <(jq -r 'keys[]' "$REGISTRY")

  echo "Services to update: ${#SERVICE_LIST[@]}"
  echo ""
  for svc in "${SERVICE_LIST[@]}"; do
    echo "  • $svc ($(jq -r --arg s "$svc" '.[$s].domain' "$REGISTRY"):$(jq -r --arg s "$svc" '.[$s].port' "$REGISTRY"))"
  done
  echo ""

elif [ -n "$TARGET_SERVICE" ]; then
  if ! jq -e --arg s "$TARGET_SERVICE" '.[$s]' "$REGISTRY" > /dev/null 2>&1; then
    fail "Service '$TARGET_SERVICE' not found in registry"
  fi

  SERVICE_LIST=("$TARGET_SERVICE")

  echo "Service to update: $TARGET_SERVICE"
  echo "Domain: $(jq -r --arg s "$TARGET_SERVICE" '.[$s].domain' "$REGISTRY")"
  echo "Port: $(jq -r --arg s "$TARGET_SERVICE" '.[$s].port' "$REGISTRY")"
  echo ""

else
  echo "Available services:"
  echo ""
  jq -r 'to_entries[] | "  • \(.key) (\(.value.domain):\(.value.port))"' "$REGISTRY"
  echo ""
  echo "Options:"
  echo "  • Enter service name to update one service"
  echo "  • Type 'all' to update all services"
  echo ""
  read -r -p "Service name (or 'all'): " INPUT

  if [ "$INPUT" == "all" ]; then
    mapfile -t SERVICE_LIST < <(jq -r 'keys[]' "$REGISTRY")
  else
    if ! jq -e --arg s "$INPUT" '.[$s]' "$REGISTRY" > /dev/null 2>&1; then
      fail "Service '$INPUT' not found"
    fi
    SERVICE_LIST=("$INPUT")
  fi
fi

SERVICE_COUNT="${#SERVICE_LIST[@]}"
[ "$SERVICE_COUNT" -gt 0 ] || fail "No services selected"

# -------------------------------------------------
# Confirmation
# -------------------------------------------------
if [ -z "$AUTO_YES" ]; then
  echo ""
  echo "This will update $SERVICE_COUNT service(s):"
  echo "  • Redeploy main.py from the current Tixa template"
  echo "  • Reinstall dependencies from the pinned requirements file"
  echo "  • Move the service off root onto its own restricted account"
  echo "  • Rebind the app to 127.0.0.1 and refresh the Nginx routes"
  echo ""
  echo "Each service is health-checked after restart and rolled back if it fails."
  echo "Downtime per service: a few seconds (during restart)"
  echo ""
  read -r -p "Continue? (yes/no): " CONFIRM

  if [ "$CONFIRM" != "yes" ]; then
    echo "Update cancelled."
    exit 0
  fi
fi

# -------------------------------------------------
# Pre-update checks
# -------------------------------------------------
echo ""
log_info "Running pre-update checks..."

if ! command -v ffmpeg >/dev/null 2>&1; then
  log_warning "FFmpeg not found. Installing..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y ffmpeg > /dev/null 2>&1
  log_success "FFmpeg installed"
else
  log_success "FFmpeg already installed"
fi

log_success "Pre-update checks passed"

tixa_install_nginx_limits "$BASE_DIR"

# -------------------------------------------------
# Update each service
# -------------------------------------------------
UPDATED_COUNT=0
FAILED_COUNT=0
FAILED_SERVICES=()

# Set while a service is part-way through being replaced. If anything aborts the
# script in that window, the trap below puts that service back before exiting,
# instead of leaving it running new code that was never health-checked.
IN_FLIGHT=0

abort_handler() {
  local code=$?
  trap - ERR EXIT
  set +e

  if [ "$IN_FLIGHT" -eq 1 ]; then
    echo ""
    log_error "Update aborted unexpectedly while replacing '${SERVICE:-unknown}'."
    rollback_service "Unexpected failure."
  fi
  exit "$code"
}
trap abort_handler ERR EXIT

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Regenerate the site config and re-attach the existing certificate.
#
# Rendering the template alone would discard the listen/ssl directives Certbot
# added, silently turning an HTTPS site back into HTTP. `certbot install` reuses
# the certificate already on disk, so this costs no rate-limit quota.
refresh_nginx_site() {
  local service="$1" domain="$2" port="$3" backup="$4"
  local site="/etc/nginx/sites-available/${service}.conf"

  [ -f "$site" ] || return 0
  cp -p "$site" "$backup" || return 1

  sed \
    -e "s/{{PROJECT}}/${service}/g" \
    -e "s/{{DOMAIN}}/${domain}/g" \
    -e "s/{{PORT}}/${port}/g" \
    "$BASE_DIR/templates/nginx.conf.tpl" > "$site" || return 1

  ln -sf "$site" "/etc/nginx/sites-enabled/${service}.conf" || return 1

  if [ -d "/etc/letsencrypt/live/${domain}" ]; then
    if ! certbot install --cert-name "$domain" --nginx --non-interactive >/dev/null 2>&1; then
      return 1
    fi
  fi

  nginx -t >/dev/null 2>&1
}

restore_nginx_site() {
  local service="$1" backup="$2"
  local site="/etc/nginx/sites-available/${service}.conf"

  [ -f "$backup" ] || return 0
  cp -p "$backup" "$site"
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx || true
  fi
}

for SERVICE in "${SERVICE_LIST[@]}"; do
  echo "Updating service: $SERVICE"
  echo "─────────────────────────────────────────────────────"

  DOMAIN=$(jq -r --arg s "$SERVICE" '.[$s].domain' "$REGISTRY")
  PORT=$(jq -r --arg s "$SERVICE" '.[$s].port' "$REGISTRY")
  API_KEY=$(jq -r --arg s "$SERVICE" '.[$s].api_key' "$REGISTRY")

  SERVICE_DIR="/opt/${SERVICE}-processor"
  MAIN_PY="$SERVICE_DIR/main.py"
  VENV_DIR="$SERVICE_DIR/venv"
  UNIT_FILE="/etc/systemd/system/${SERVICE}-processor.service"
  SERVICE_NAME="${SERVICE}-processor"
  SERVICE_USER="$(tixa_service_user "$SERVICE")"

  MAIN_BACKUP="$MAIN_PY.backup-$TIMESTAMP"
  UNIT_BACKUP="$BACKUP_DIR/${SERVICE}-${TIMESTAMP}.service"
  NGINX_BACKUP="$BACKUP_DIR/${SERVICE}-${TIMESTAMP}.nginx.conf"

  if [ ! -d "$SERVICE_DIR" ]; then
    log_error "Service directory not found: $SERVICE_DIR"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_SERVICES+=("$SERVICE (directory not found)")
    continue
  fi
  if [ ! -x "$VENV_DIR/bin/python" ]; then
    log_error "Virtual environment not found: $VENV_DIR"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_SERVICES+=("$SERVICE (no virtual environment)")
    continue
  fi

  # Roll this service back to exactly what was on disk before we touched it.
  rollback_service() {
    local reason="$1"
    log_error "$reason Rolling back..."

    if [ -f "$MAIN_BACKUP" ]; then
      mv -f "$MAIN_BACKUP" "$MAIN_PY"
    fi
    if [ -f "$UNIT_BACKUP" ]; then
      cp -p "$UNIT_BACKUP" "$UNIT_FILE"
      systemctl daemon-reload || true
    fi
    restore_nginx_site "$SERVICE" "$NGINX_BACKUP"

    systemctl restart "$SERVICE_NAME" >/dev/null 2>&1 || true

    if tixa_wait_for_health "$SERVICE" "$PORT"; then
      log_success "Rolled back to the previous version (healthy)"
    else
      log_error "ROLLBACK DID NOT RECOVER '$SERVICE'."
      log_error "Backups kept in $BACKUP_DIR — inspect: journalctl -u $SERVICE_NAME -n 50"
    fi
    IN_FLIGHT=0
  }

  # Step 1: Backup
  if [ -z "$SKIP_BACKUP" ]; then
    log_info "Creating backup..."
    BACKUP_FILE="$BACKUP_DIR/${SERVICE}-${TIMESTAMP}.tar.gz"
    tar -czf "$BACKUP_FILE" -C "$SERVICE_DIR" . 2>/dev/null || true
    log_success "Backup created: $BACKUP_FILE"
  fi

  if [ -f "$UNIT_FILE" ]; then cp -p "$UNIT_FILE" "$UNIT_BACKUP"; fi

  # Step 2: Dependencies, from the pinned set the template was tested against
  log_info "Installing dependencies..."
  if ! "$VENV_DIR/bin/pip" install --quiet --upgrade pip >/dev/null 2>&1 \
     || ! "$VENV_DIR/bin/pip" install --quiet -r "$REQUIREMENTS_FILE"; then
    log_error "Dependency installation failed"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_SERVICES+=("$SERVICE (dependency install failed)")
    continue
  fi
  log_success "Dependencies updated"

  # Step 3: Backup current main.py
  if [ -f "$MAIN_PY" ]; then
    cp -p "$MAIN_PY" "$MAIN_BACKUP"
    log_success "Current main.py backed up"
  fi

  # Step 4: Deploy new main.py
  log_info "Deploying updated main.py..."
  IN_FLIGHT=1
  sed \
    -e "s/{{PROJECT}}/${SERVICE}/g" \
    -e "s/{{API_KEY}}/${API_KEY}/g" \
    -e "s|{{BASE_URL}}|https://${DOMAIN}|g" \
    "$BASE_DIR/templates/main.py" \
    > "$MAIN_PY"
  log_success "New main.py deployed"

  # Step 5: Verify syntax with the interpreter that will actually run it
  log_info "Verifying Python syntax..."
  if PYTHONPYCACHEPREFIX="$(mktemp -d)" "$VENV_DIR/bin/python" -m py_compile "$MAIN_PY" 2>/dev/null; then
    log_success "Syntax check passed"
  else
    if [ -f "$MAIN_BACKUP" ]; then mv -f "$MAIN_BACKUP" "$MAIN_PY"; fi
    log_error "Syntax check failed! Restored the previous main.py."
    IN_FLIGHT=0
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_SERVICES+=("$SERVICE (syntax error)")
    continue
  fi

  # Step 6: Move the service onto its own account and the hardened unit
  log_info "Applying the hardened systemd unit..."
  tixa_ensure_service_user "$SERVICE_USER"
  tixa_apply_ownership "$SERVICE" "$SERVICE_USER"

  sed \
    -e "s/{{PROJECT}}/${SERVICE}/g" \
    -e "s/{{PORT}}/${PORT}/g" \
    -e "s/{{SERVICE_USER}}/${SERVICE_USER}/g" \
    "$BASE_DIR/templates/service.tpl" \
    > "$UNIT_FILE"
  systemctl daemon-reload

  # Step 7: Restart and require a healthy response
  log_info "Restarting service..."
  if ! systemctl restart "$SERVICE_NAME" 2>/dev/null; then
    rollback_service "Service failed to restart."
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_SERVICES+=("$SERVICE (restart failed)")
    continue
  fi

  # `systemctl is-active` reports a process that is still importing modules as
  # active and will report a crash-looping unit as active between restarts.
  # Only a 200 from /health means the deployment actually works.
  log_info "Verifying health endpoint..."
  if ! tixa_wait_for_health "$SERVICE" "$PORT"; then
    rollback_service "Service did not report healthy within ${TIXA_HEALTH_TIMEOUT}s."
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_SERVICES+=("$SERVICE (health check failed)")
    continue
  fi
  log_success "Service is healthy"

  # Step 8: Refresh the Nginx routes
  log_info "Refreshing Nginx configuration..."
  if refresh_nginx_site "$SERVICE" "$DOMAIN" "$PORT" "$NGINX_BACKUP"; then
    systemctl reload nginx
    log_success "Nginx configuration updated"
  else
    log_warning "Nginx refresh failed; restored the previous site configuration"
    restore_nginx_site "$SERVICE" "$NGINX_BACKUP"
  fi

  # Step 9: Record the service account, then drop the per-file backups
  REGISTRY_CANDIDATE="$REGISTRY.update-new"
  if jq --arg s "$SERVICE" --arg user "$SERVICE_USER" \
        '.[$s].service_user = $user' "$REGISTRY" > "$REGISTRY_CANDIDATE"; then
    tixa_commit_registry "$REGISTRY" "$REGISTRY_CANDIDATE"
  else
    rm -f "$REGISTRY_CANDIDATE"
    log_warning "Could not record the service account in the registry"
  fi

  rm -f "$MAIN_BACKUP" "$NGINX_BACKUP"
  IN_FLIGHT=0

  UPDATED_COUNT=$((UPDATED_COUNT + 1))

  echo ""
  log_success "Service '$SERVICE' updated successfully!"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
done

# -------------------------------------------------
# Summary
# -------------------------------------------------
echo ""
echo "📊 UPDATE SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Total services: $SERVICE_COUNT"
echo "Updated: $UPDATED_COUNT"
echo "Failed: $FAILED_COUNT"
echo ""

if [ "$FAILED_COUNT" -gt 0 ]; then
  echo "Failed services:"
  printf '  • %s\n' "${FAILED_SERVICES[@]}"
  echo ""
fi

if [ "$UPDATED_COUNT" -gt 0 ]; then
  echo "📚 Verify your services:"
  for SERVICE in "${SERVICE_LIST[@]}"; do
    if systemctl is-active --quiet "${SERVICE}-processor"; then
      echo "  • https://$(jq -r --arg s "$SERVICE" '.[$s].domain' "$REGISTRY")/health"
    fi
  done
  echo ""
fi

if [ -z "$SKIP_BACKUP" ]; then
  echo "💾 Backups saved to: $BACKUP_DIR"
  echo ""
fi

if [ "$FAILED_COUNT" -eq 0 ]; then
  echo "🎉 All services updated successfully!"
  exit 0
fi

echo "⚠️  Some services failed to update. Check the log above."
exit 1
