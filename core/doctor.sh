#!/usr/bin/env bash
set -uo pipefail

QUIET="${1:-}"
ERRORS=()
WARNINGS=()

error() { ERRORS+=("$1"); }
warning() { WARNINGS+=("$1"); }

if [ "$(id -u)" -ne 0 ]; then
  error "Run this check as root: sudo tixa doctor"
fi

if [ ! -r /etc/os-release ]; then
  error "Unable to identify the operating system"
else
  . /etc/os-release
  case "${ID:-}:${ID_LIKE:-}" in
    *debian*|*ubuntu*) ;;
    *) error "Unsupported OS: ${PRETTY_NAME:-unknown}; use Debian or Ubuntu" ;;
  esac
fi

if [ "$(ps -p 1 -o comm= 2>/dev/null | tr -d ' ')" != "systemd" ]; then
  error "systemd is not running as PID 1; Tixa cannot manage services"
fi

for command_name in python3 nginx certbot ffmpeg vips jq dig curl openssl git systemctl ss; do
  command -v "$command_name" >/dev/null 2>&1 || error "Missing command: $command_name"
done

for competing_service in apache2 caddy lighttpd; do
  if systemctl is-active --quiet "$competing_service" 2>/dev/null; then
    error "Competing web server is active: $competing_service"
  fi
done

if command -v ss >/dev/null 2>&1; then
  PORT_OWNERS="$(ss -ltnp 2>/dev/null | awk '$4 ~ /:80$|:443$/ {print}' || true)"
  if [ -n "$PORT_OWNERS" ] && ! grep -q 'nginx' <<< "$PORT_OWNERS"; then
    error "Ports 80/443 are occupied by a non-Nginx process: $PORT_OWNERS"
  fi
fi

if command -v nginx >/dev/null 2>&1; then
  nginx -t >/dev/null 2>&1 || error "The existing Nginx configuration is invalid (run: sudo nginx -t)"
  systemctl is-active --quiet nginx 2>/dev/null || error "Nginx is not running"
fi

if command -v certbot >/dev/null 2>&1; then
  certbot plugins 2>/dev/null | grep -q 'nginx' || error "Certbot's Nginx plugin is unavailable"
fi

if command -v python3 >/dev/null 2>&1; then
  TEST_VENV="$(mktemp -d /tmp/tixa-venv-check.XXXXXX)"
  if ! python3 -m venv "$TEST_VENV/venv" >/dev/null 2>&1; then
    error "Python cannot create virtual environments; install the matching python3-venv package"
  fi
  rm -rf "$TEST_VENV"
fi

if [ "$QUIET" != "--quiet" ]; then
  echo ""
  echo "TIXA SYSTEM CHECK"
  echo "---------------------------"
  for item in "${WARNINGS[@]}"; do echo "WARNING: $item"; done
  for item in "${ERRORS[@]}"; do echo "ERROR: $item"; done
fi

if [ "${#ERRORS[@]}" -gt 0 ]; then
  if [ "$QUIET" = "--quiet" ]; then
    echo "Tixa preflight failed:"
    for item in "${ERRORS[@]}"; do echo "  - $item"; done
  fi
  exit 1
fi

if [ "$QUIET" != "--quiet" ]; then
  echo "READY: this server is compatible with Tixa"
fi
