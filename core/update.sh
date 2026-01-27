#!/usr/bin/env bash
set -e

# -------------------------------------------------
# TIXA UPDATE - Safely update running services
# -------------------------------------------------

BASE_DIR="/opt/tixa"
STATE_DIR="/var/lib/tixa"
REGISTRY="$STATE_DIR/registry.json"
BACKUP_DIR="/var/backups/tixa-updates"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

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
log_info() {
  echo -e "${BLUE}▶${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

fail() {
  echo ""
  log_error "$1"
  echo ""
  exit 1
}

# -------------------------------------------------
# Startup checks
# -------------------------------------------------
if [ ! -f "$REGISTRY" ]; then
  fail "No services found. Registry file does not exist."
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# -------------------------------------------------
# Parse arguments
# -------------------------------------------------
TARGET_SERVICE="$1"
SKIP_BACKUP=""
AUTO_YES=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-backup)
      SKIP_BACKUP="yes"
      shift
      ;;
    --yes|-y)
      AUTO_YES="yes"
      shift
      ;;
    --all)
      TARGET_SERVICE="--all"
      shift
      ;;
    *)
      if [ -z "$TARGET_SERVICE" ]; then
        TARGET_SERVICE="$1"
      fi
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
  SERVICES=$(jq -r 'keys[]' "$REGISTRY")
  SERVICE_COUNT=$(echo "$SERVICES" | wc -l)
  
  echo "Services to update: $SERVICE_COUNT"
  echo ""
  echo "$SERVICES" | while read -r svc; do
    DOMAIN=$(jq -r ".\"$svc\".domain" "$REGISTRY")
    PORT=$(jq -r ".\"$svc\".port" "$REGISTRY")
    echo "  • $svc ($DOMAIN:$PORT)"
  done
  echo ""
  
elif [ -n "$TARGET_SERVICE" ]; then
  # Check if service exists
  if ! jq -e ".\"$TARGET_SERVICE\"" "$REGISTRY" > /dev/null 2>&1; then
    fail "Service '$TARGET_SERVICE' not found in registry"
  fi
  
  SERVICES="$TARGET_SERVICE"
  SERVICE_COUNT=1
  
  DOMAIN=$(jq -r ".\"$TARGET_SERVICE\".domain" "$REGISTRY")
  PORT=$(jq -r ".\"$TARGET_SERVICE\".port" "$REGISTRY")
  
  echo "Service to update: $TARGET_SERVICE"
  echo "Domain: $DOMAIN"
  echo "Port: $PORT"
  echo ""
  
else
  # Interactive selection
  echo "Available services:"
  echo ""
  
  jq -r 'keys[]' "$REGISTRY" | while read -r svc; do
    DOMAIN=$(jq -r ".\"$svc\".domain" "$REGISTRY")
    PORT=$(jq -r ".\"$svc\".port" "$REGISTRY")
    echo "  • $svc ($DOMAIN:$PORT)"
  done
  
  echo ""
  echo "Options:"
  echo "  • Enter service name to update one service"
  echo "  • Type 'all' to update all services"
  echo ""
  read -p "Service name (or 'all'): " INPUT
  
  if [ "$INPUT" == "all" ]; then
    SERVICES=$(jq -r 'keys[]' "$REGISTRY")
    SERVICE_COUNT=$(echo "$SERVICES" | wc -l)
  else
    if ! jq -e ".\"$INPUT\"" "$REGISTRY" > /dev/null 2>&1; then
      fail "Service '$INPUT' not found"
    fi
    SERVICES="$INPUT"
    SERVICE_COUNT=1
  fi
fi

# -------------------------------------------------
# Confirmation
# -------------------------------------------------
if [ -z "$AUTO_YES" ]; then
  echo ""
  echo "This will update $SERVICE_COUNT service(s) with:"
  echo "  • New audio support (10 formats)"
  echo "  • Updated dependencies (numpy, matplotlib)"
  echo "  • Enhanced main.py with audio endpoints"
  echo ""
  echo "Downtime per service: ~1-2 seconds (during restart)"
  echo ""
  read -p "Continue? (yes/no): " CONFIRM
  
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

# Check if FFmpeg is installed
if ! command -v ffmpeg &> /dev/null; then
  log_warning "FFmpeg not found. Installing..."
  apt-get update -qq
  apt-get install -y ffmpeg > /dev/null 2>&1
  log_success "FFmpeg installed"
else
  log_success "FFmpeg already installed"
fi

# Check if templates exist
if [ ! -f "$BASE_DIR/templates/main.py" ]; then
  fail "Template file not found: $BASE_DIR/templates/main.py"
fi

log_success "Pre-update checks passed"

# -------------------------------------------------
# Update each service
# -------------------------------------------------
UPDATED_COUNT=0
FAILED_COUNT=0
FAILED_SERVICES=""

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for SERVICE in $SERVICES; do
  echo "Updating service: $SERVICE"
  echo "─────────────────────────────────────────────────────"
  
  # Get service details
  DOMAIN=$(jq -r ".\"$SERVICE\".domain" "$REGISTRY")
  PORT=$(jq -r ".\"$SERVICE\".port" "$REGISTRY")
  API_KEY=$(jq -r ".\"$SERVICE\".api_key" "$REGISTRY")
  
  SERVICE_DIR="/opt/${SERVICE}-processor"
  MAIN_PY="$SERVICE_DIR/main.py"
  VENV_DIR="$SERVICE_DIR/venv"
  
  # Validate service directory exists
  if [ ! -d "$SERVICE_DIR" ]; then
    log_error "Service directory not found: $SERVICE_DIR"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_SERVICES="$FAILED_SERVICES\n  • $SERVICE (directory not found)"
    continue
  fi
  
  # Step 1: Backup
  if [ -z "$SKIP_BACKUP" ]; then
    log_info "Creating backup..."
    BACKUP_FILE="$BACKUP_DIR/${SERVICE}-${TIMESTAMP}.tar.gz"
    tar -czf "$BACKUP_FILE" -C "$SERVICE_DIR" . 2>/dev/null
    log_success "Backup created: $BACKUP_FILE"
  fi
  
  # Step 2: Update Python dependencies
  log_info "Installing new dependencies..."
  
  if [ -f "$VENV_DIR/bin/activate" ]; then
    source "$VENV_DIR/bin/activate"
    
    # Install new audio dependencies
    pip install --quiet --upgrade pip
    pip install --quiet numpy>=1.24.0 matplotlib>=3.7.0
    
    deactivate
    log_success "Dependencies updated"
  else
    log_warning "Virtual environment not found, skipping pip install"
  fi
  
  # Step 3: Backup current main.py
  if [ -f "$MAIN_PY" ]; then
    cp "$MAIN_PY" "$MAIN_PY.backup-$TIMESTAMP"
    log_success "Current main.py backed up"
  fi
  
  # Step 4: Deploy new main.py
  log_info "Deploying updated main.py..."
  
  sed \
    -e "s/{{PROJECT}}/${SERVICE}/g" \
    -e "s/{{API_KEY}}/${API_KEY}/g" \
    -e "s|{{BASE_URL}}|https://${DOMAIN}|g" \
    "$BASE_DIR/templates/main.py" \
    > "$MAIN_PY"
  
  log_success "New main.py deployed"
  
  # Step 5: Verify syntax
  log_info "Verifying Python syntax..."
  
  if python3 -m py_compile "$MAIN_PY" 2>/dev/null; then
    log_success "Syntax check passed"
  else
    log_error "Syntax check failed! Rolling back..."
    
    # Rollback
    if [ -f "$MAIN_PY.backup-$TIMESTAMP" ]; then
      mv "$MAIN_PY.backup-$TIMESTAMP" "$MAIN_PY"
      log_success "Rolled back to previous version"
    fi
    
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_SERVICES="$FAILED_SERVICES\n  • $SERVICE (syntax error)"
    continue
  fi
  
  # Step 6: Restart service
  log_info "Restarting service (1-2 sec downtime)..."
  
  SERVICE_NAME="${SERVICE}-processor"
  
  if systemctl restart "$SERVICE_NAME" 2>/dev/null; then
    sleep 2
    
    # Verify service is running
    if systemctl is-active --quiet "$SERVICE_NAME"; then
      log_success "Service restarted successfully"
    else
      log_error "Service failed to start! Rolling back..."
      
      # Rollback
      if [ -f "$MAIN_PY.backup-$TIMESTAMP" ]; then
        mv "$MAIN_PY.backup-$TIMESTAMP" "$MAIN_PY"
        systemctl restart "$SERVICE_NAME" 2>/dev/null
        log_success "Rolled back to previous version"
      fi
      
      FAILED_COUNT=$((FAILED_COUNT + 1))
      FAILED_SERVICES="$FAILED_SERVICES\n  • $SERVICE (failed to start)"
      continue
    fi
  else
    log_error "Failed to restart service"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_SERVICES="$FAILED_SERVICES\n  • $SERVICE (restart failed)"
    continue
  fi
  
  # Step 7: Verify health endpoint
  log_info "Verifying health endpoint..."
  
  sleep 1
  
  HEALTH_CHECK=$(curl -s "http://localhost:$PORT/health" 2>/dev/null || echo "")
  
  if echo "$HEALTH_CHECK" | grep -q "audio"; then
    log_success "Audio support verified ✨"
  else
    log_warning "Health check returned unexpected response"
  fi
  
  # Step 8: Cleanup old backup
  if [ -f "$MAIN_PY.backup-$TIMESTAMP" ]; then
    rm "$MAIN_PY.backup-$TIMESTAMP"
  fi
  
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

if [ $FAILED_COUNT -gt 0 ]; then
  echo "Failed services:"
  echo -e "$FAILED_SERVICES"
  echo ""
fi

if [ $UPDATED_COUNT -gt 0 ]; then
  echo "✨ New features available:"
  echo "  • Audio file support (MP3, WAV, FLAC, AAC, OGG, M4A, WMA, OPUS, AIFF)"
  echo "  • Waveform generation endpoint"
  echo "  • Audio streaming endpoint"
  echo "  • Format conversion endpoint"
  echo ""
  
  echo "📚 Test your services:"
  for SERVICE in $SERVICES; do
    if systemctl is-active --quiet "${SERVICE}-processor"; then
      DOMAIN=$(jq -r ".\"$SERVICE\".domain" "$REGISTRY")
      echo "  • https://${DOMAIN}/health"
    fi
  done
  echo ""
fi

if [ -z "$SKIP_BACKUP" ]; then
  echo "💾 Backups saved to: $BACKUP_DIR"
  echo ""
fi

if [ $FAILED_COUNT -eq 0 ]; then
  echo "🎉 All services updated successfully!"
else
  echo "⚠️  Some services failed to update. Check logs above."
fi

echo ""
