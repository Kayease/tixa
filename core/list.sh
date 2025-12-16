#!/usr/bin/env bash

set -e

STATE_DIR="/var/lib/tixa"
REGISTRY="$STATE_DIR/registry.json"

echo ""
echo "📦 TIXA · SERVICES"
echo "--------------------------"

# If registry does not exist or is empty
if [ ! -f "$REGISTRY" ] || [ "$(jq 'length' "$REGISTRY")" -eq 0 ]; then
  echo "No services found."
  exit 0
fi

jq -r '
  to_entries[] |
  "Project : \(.key)\nDomain  : \(.value.domain)\nPort    : \(.value.port)\nAPI Key : \(.value.api_key)\n--------------------------"
' "$REGISTRY"
