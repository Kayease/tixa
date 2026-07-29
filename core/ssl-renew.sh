#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/var/lib/tixa"
REGISTRY="$STATE_DIR/registry.json"
TARGET="${1:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: run this command with sudo"
  exit 1
fi

if [ ! -f "$REGISTRY" ]; then
  echo "Error: no Tixa services are registered"
  exit 1
fi

renew_project() {
  local project="$1"
  local domain

  if ! jq -e --arg project "$project" '.[$project]' "$REGISTRY" >/dev/null; then
    echo "Error: service '$project' was not found"
    return 1
  fi

  domain="$(jq -r --arg project "$project" '.[$project].domain' "$REGISTRY")"
  echo "Renewing SSL certificate for $project ($domain)..."
  certbot --nginx --cert-name "$domain" -d "$domain" --non-interactive
  jq --arg project "$project" '.[$project].ssl = "installed"' "$REGISTRY" > "$REGISTRY.tmp"
  mv "$REGISTRY.tmp" "$REGISTRY"
  chmod 600 "$REGISTRY"
}

if [ "$TARGET" = "all" ]; then
  while IFS= read -r project; do
    renew_project "$project"
  done < <(jq -r 'keys[]' "$REGISTRY")
elif [ -n "$TARGET" ]; then
  renew_project "${TARGET,,}"
else
  echo "Usage: tixa ssl renew <project|--all>"
  exit 1
fi

systemctl reload nginx
