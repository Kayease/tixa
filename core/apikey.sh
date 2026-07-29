#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/tixa"
STATE_DIR="/var/lib/tixa"
REGISTRY="$STATE_DIR/registry.json"
ACTION="${1:-}"
TARGET="${2:-}"
OPTION="${3:-}"

# shellcheck source=/opt/tixa/core/common.sh
source "$BASE_DIR/core/common.sh"

fail() { echo "Error: $1"; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "run as root: sudo tixa apikey rotate <service|--all>"
[ "$ACTION" = "rotate" ] || fail "usage: tixa apikey rotate <service|--all> [--yes]"
[ -f "$REGISTRY" ] || fail "no Tixa services are registered"
[ -n "$TARGET" ] || fail "specify a service name or --all"

if [ "$TARGET" = "--all" ]; then
  mapfile -t SERVICES < <(jq -r 'keys[]' "$REGISTRY")
else
  TARGET="${TARGET,,}"
  jq -e --arg project "$TARGET" '.[$project]' "$REGISTRY" >/dev/null || fail "service '$TARGET' not found"
  SERVICES=("$TARGET")
fi

[ "${#SERVICES[@]}" -gt 0 ] || fail "no services found"

echo "API key rotation will immediately invalidate the current key for:"
printf '  - %s\n' "${SERVICES[@]}"
echo "Applications using these services must be updated with the new keys."

if [ "$OPTION" != "--yes" ] && [ "$OPTION" != "-y" ]; then
  read -r -p "Type ROTATE to continue: " CONFIRM
  [ "$CONFIRM" = "ROTATE" ] || fail "cancelled"
fi

restore_previous_key() {
  local service="$1" port="$2" main_file="$3" old_main="$4"
  mv -f "$old_main" "$main_file"
  systemctl restart "${service}-processor" >/dev/null 2>&1 || true
  if tixa_wait_for_health "$service" "$port"; then
    echo "Restored the previous API key for $service"
    return 0
  fi
  echo "WARNING: $service did not become healthy after restoring the previous key."
  echo "         Inspect it with: journalctl -u ${service}-processor -n 50"
  return 1
}

rotate_service() {
  local service="$1"
  local port new_key service_dir main_file candidate old_main registry_candidate

  port="$(jq -r --arg project "$service" '.[$project].port' "$REGISTRY")"
  [ -n "$port" ] && [ "$port" != "null" ] || { echo "Failed $service: no port recorded in the registry"; return 1; }

  new_key="${service}_live_$(openssl rand -hex 16)"
  service_dir="/opt/${service}-processor"
  main_file="$service_dir/main.py"
  candidate="$service_dir/main.py.rotate-new"
  old_main="$service_dir/main.py.rotate-old"
  registry_candidate="$REGISTRY.rotate-new"

  [ -x "$service_dir/venv/bin/python" ] || { echo "Failed $service: virtual environment not found"; return 1; }
  [ -f "$main_file" ] || { echo "Failed $service: main.py not found"; return 1; }
  [ ! -e "$old_main" ] || { echo "Failed $service: $old_main exists from an interrupted rotation; resolve it first"; return 1; }

  sed -E "s|^API_KEY = .*|API_KEY = \"${new_key}\"|" "$main_file" > "$candidate"
  if ! grep -Fxq "API_KEY = \"${new_key}\"" "$candidate"; then
    rm -f "$candidate"
    echo "Failed $service: API_KEY setting was not found in main.py"
    return 1
  fi

  # set -e is suspended inside a function invoked with `||`, so check explicitly.
  if ! PYTHONPYCACHEPREFIX="$(mktemp -d)" "$service_dir/venv/bin/python" -m py_compile "$candidate"; then
    rm -f "$candidate"
    echo "Failed $service: the rewritten main.py does not compile"
    return 1
  fi

  cp -p "$main_file" "$old_main"
  mv -f "$candidate" "$main_file"
  chown --reference="$old_main" "$main_file" 2>/dev/null || true

  if ! systemctl restart "${service}-processor"; then
    echo "Rotation failed for $service: the service did not restart; restoring the previous API key"
    restore_previous_key "$service" "$port" "$main_file" "$old_main" || return 1
    return 1
  fi

  if ! tixa_wait_for_health "$service" "$port"; then
    echo "Rotation failed for $service: it did not report healthy within ${TIXA_HEALTH_TIMEOUT}s; restoring the previous API key"
    restore_previous_key "$service" "$port" "$main_file" "$old_main" || return 1
    return 1
  fi

  if ! jq --arg project "$service" --arg key "$new_key" '.[$project].api_key = $key' "$REGISTRY" > "$registry_candidate"; then
    rm -f "$registry_candidate"
    echo "Registry update failed for $service; restoring the previous API key"
    restore_previous_key "$service" "$port" "$main_file" "$old_main" || return 1
    return 1
  fi

  tixa_commit_registry "$REGISTRY" "$registry_candidate"
  rm -f "$old_main"
  echo "Rotated $service"
  echo "New API key: $new_key"
}

FAILED=0
ROTATED=()
for SERVICE in "${SERVICES[@]}"; do
  if rotate_service "$SERVICE"; then
    ROTATED+=("$SERVICE")
  else
    FAILED=$((FAILED + 1))
  fi
done

if [ "$FAILED" -gt 0 ]; then
  if [ "${#ROTATED[@]}" -gt 0 ]; then
    echo ""
    echo "Keys that were rotated successfully and are now live:"
    printf '  - %s\n' "${ROTATED[@]}"
    echo "These were kept; only the failed services still use their previous key."
  fi
  fail "$FAILED service(s) could not be rotated"
fi

echo "API key rotation completed successfully"
