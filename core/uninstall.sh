#!/usr/bin/env bash
set -e

MODE="$1"

BASE_DIR="/opt/tixa"
STATE_DIR="/var/lib/tixa"
REGISTRY="$STATE_DIR/registry.json"

echo ""
echo "🧹 TIXA · UNINSTALL"
echo "---------------------------"

if [ "$MODE" == "--hard" ]; then
  echo "⚠️  HARD UNINSTALL SELECTED"
  echo "This will remove:"
  echo "• All Tixa services"
  echo "• Registry"
  echo "• SSL email"
  echo "• Tixa runtime"
  echo ""
  read -p "Type UNINSTALL to confirm: " CONFIRM

  if [ "$CONFIRM" != "UNINSTALL" ]; then
    echo "❌ Cancelled"
    exit 1
  fi

  if [ -f "$REGISTRY" ]; then
    jq -r 'keys[]' "$REGISTRY" | while read -r PROJECT; do
      echo ""
      echo "▶ Removing service: $PROJECT"
      bash "$BASE_DIR/core/delete.sh" "$PROJECT" --force
    done
  fi

  echo ""
  echo "▶ Removing state directory"
  rm -rf "$STATE_DIR"

else
  echo "Soft uninstall:"
  echo "• Removes Tixa CLI & runtime only"
  echo "• Keeps services, registry & SSL email"
  echo ""
  read -p "Type UNINSTALL to confirm: " CONFIRM

  if [ "$CONFIRM" != "UNINSTALL" ]; then
    echo "❌ Cancelled"
    exit 1
  fi
fi

echo ""
echo "▶ Removing Tixa runtime"
rm -rf "$BASE_DIR"
rm -f /usr/local/bin/tixa

echo ""
echo "✅ Tixa uninstalled successfully"
