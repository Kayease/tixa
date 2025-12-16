#!/usr/bin/env bash
set -e

CMD="$1"
PROJECT="$2"

case "$CMD" in
  renew)
    if [ "$PROJECT" == "--all" ]; then
      bash /opt/tixa/core/ssl-renew.sh all
    elif [ -z "$PROJECT" ]; then
      echo "❌ Project name required"
      echo "Usage:"
      echo "  tixa ssl renew <project>"
      echo "  tixa ssl renew --all"
      exit 1
    else
      bash /opt/tixa/core/ssl-renew.sh "$PROJECT"
    fi
    ;;
  *)
    echo "❌ Unknown ssl command"
    echo "Available:"
    echo "  tixa ssl renew <project>"
    ;;
esac
