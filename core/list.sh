#!/usr/bin/env bash

REGISTRY="/opt/tixa/registry/services.json"

echo ""
echo "📦 TIXA · SERVICES"
echo "--------------------------"

COUNT=$(jq 'length' "$REGISTRY")

if [ "$COUNT" -eq 0 ]; then
  echo "No services found."
  exit 0
fi

jq -r '
  to_entries[] |
  "Project : \(.key)\nDomain  : \(.value.domain)\nPort    : \(.value.port)\nAPI Key : \(.value.api_key)\n--------------------------"
' "$REGISTRY"
