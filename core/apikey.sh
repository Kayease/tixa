#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/var/lib/tixa"
REGISTRY="$STATE_DIR/registry.json"
ACTION="${1:-}"
TARGET="${2:-}"
OPTION="${3:-}"

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

rotate_service() {
  local service="$1"
  local port new_key service_dir main_file candidate old_main registry_candidate
  port="$(jq -r --arg project "$service" '.[$project].port' "$REGISTRY")"
  new_key="${service}_live_$(openssl rand -hex 16)"
  service_dir="/opt/${service}-processor"
  main_file="$service_dir/main.py"
  candidate="$service_dir/main.py.rotate-new"
  old_main="$service_dir/main.py.rotate-old"
  registry_candidate="$REGISTRY.rotate-new"

  [ -x "$service_dir/venv/bin/python" ] || { echo "Failed $service: virtual environment not found"; return 1; }
  [ -f "$main_file" ] || { echo "Failed $service: main.py not found"; return 1; }

  sed -E "s|^API_KEY = .*|API_KEY = \"${new_key}\"|" "$main_file" > "$candidate"
  grep -Fxq "API_KEY = \"${new_key}\"" "$candidate" || {
    rm -f "$candidate"
    echo "Failed $service: API_KEY setting was not found in main.py"
    return 1
  }
  "$service_dir/venv/bin/python" -m py_compile "$candidate"

  mv "$main_file" "$old_main"
  mv "$candidate" "$main_file"

  if ! systemctl restart "${service}-processor" || ! curl -fs --retry 5 --retry-delay 1 "http://127.0.0.1:${port}/health" >/dev/null; then
    echo "Rotation failed for $service; restoring the previous API key"
    mv "$old_main" "$main_file"
    systemctl restart "${service}-processor" || true
    return 1
  fi

  if ! jq --arg project "$service" --arg key "$new_key" '.[$project].api_key = $key' "$REGISTRY" > "$registry_candidate"; then
    echo "Registry update failed for $service; restoring the previous API key"
    mv "$old_main" "$main_file"
    systemctl restart "${service}-processor" || true
    rm -f "$registry_candidate"
    return 1
  fi

  mv "$registry_candidate" "$REGISTRY"
  chmod 600 "$REGISTRY"
  rm -f "$old_main"
  echo "Rotated $service"
  echo "New API key: $new_key"
}

FAILED=0
for SERVICE in "${SERVICES[@]}"; do
  rotate_service "$SERVICE" || FAILED=$((FAILED + 1))
done

if [ "$FAILED" -gt 0 ]; then
  fail "$FAILED service(s) could not be rotated; successful rotations were not reverted"
fi

echo "API key rotation completed successfully"
