#!/usr/bin/env bash
set -e

CMD="$1"
PROJECT="$2"

BASE_DIR="/opt/tixa"

case "$CMD" in
  renew)
    if [ "$PROJECT" == "--all" ]; then
      bash "$BASE_DIR/core/ssl-renew.sh" all
    elif [ -z "$PROJECT" ]; then
      echo "❌ Project name required"
      echo ""
      echo "Usage:"
      echo "  tixa ssl renew <project>"
      echo "  tixa ssl renew --all"
      exit 1
    else
      bash "$BASE_DIR/core/ssl-renew.sh" "$PROJECT"
    fi
    ;;
  *)
    echo "❌ Unknown ssl command"
    echo ""
    echo "Available:"
    echo "  tixa ssl renew <project>"
    echo "  tixa ssl renew --all"
    ;;
esac
