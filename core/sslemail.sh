#!/usr/bin/env bash
set -e

STATE_DIR="/var/lib/tixa"
EMAIL_FILE="$STATE_DIR/sslemail"

mkdir -p "$STATE_DIR"

case "$1" in
  set)
    read -p "Enter SSL email (Certbot): " EMAIL

    if [[ -z "$EMAIL" ]]; then
      echo "❌ Email cannot be empty"
      exit 1
    fi

    echo "$EMAIL" > "$EMAIL_FILE"
    chmod 600 "$EMAIL_FILE"

    echo "✅ SSL email saved successfully"
    ;;
  show)
    if [ ! -f "$EMAIL_FILE" ]; then
      echo "❌ SSL email not configured"
      echo "👉 Run: tixa sslemail set"
      exit 1
    fi

    echo ""
    echo "📧 SSL Email"
    echo "-----------------"
    cat "$EMAIL_FILE"
    ;;
  *)
    echo ""
    echo "Usage:"
    echo "  tixa sslemail set"
    echo "  tixa sslemail show"
    ;;
esac
