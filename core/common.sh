#!/usr/bin/env bash
# Shared helpers for the Tixa core scripts. Sourced, never executed directly.

TIXA_HEALTH_TIMEOUT="${TIXA_HEALTH_TIMEOUT:-60}"

# Derive the dedicated system account for a service. Linux user names are
# capped at 32 characters, so long project names fall back to a digest.
tixa_service_user() {
  local project="$1" name="tixa-$1"
  if [ "${#name}" -gt 31 ]; then
    name="tixa-$(printf '%s' "$project" | sha256sum | cut -c1-20)"
  fi
  printf '%s' "$name"
}

tixa_ensure_service_user() {
  local user="$1"
  if ! getent group "$user" >/dev/null 2>&1; then
    groupadd --system "$user"
  fi
  if ! id -u "$user" >/dev/null 2>&1; then
    useradd --system --gid "$user" --no-create-home \
      --home-dir /nonexistent --shell /usr/sbin/nologin "$user"
  fi
}

# Give a service ownership of its own media tree, and nothing else. The
# application directory stays root-owned so a compromised worker cannot rewrite
# its own code.
tixa_apply_ownership() {
  local project="$1" user="$2"
  local media="/var/www/images/${project}"
  local application="/opt/${project}-processor"

  if [ -d "$media" ]; then
    # Matplotlib and fontconfig write here; see MPLCONFIGDIR in service.tpl.
    mkdir -p "$media/.cache"
    chown -R "${user}:${user}" "$media"
    chmod 755 "$media"
  fi
  if [ -d "$application" ]; then
    chown -R root:root "$application"
    chmod -R go-w "$application"
  fi
}

# Poll /health until it answers 200.
#
# systemd returns from `restart` as soon as the process is forked, but uvicorn
# needs several seconds to import pyvips, PyMuPDF, NumPy and Matplotlib before
# it binds its port. During that window the connection is refused, and
# `curl --retry` does NOT retry connection-refused errors, so a single probe
# reports a perfectly healthy deployment as failed.
tixa_wait_for_health() {
  local service="$1" port="$2" timeout="${3:-$TIXA_HEALTH_TIMEOUT}" deadline
  deadline=$(( SECONDS + timeout ))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if systemctl is-failed --quiet "${service}-processor" 2>/dev/null; then
      return 1
    fi
    if curl -fsS --max-time 5 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

tixa_port_in_use() {
  local port="$1"
  if ss -ltnH "sport = :${port}" 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

# Pick a loopback port that is free right now, not recorded in the registry, and
# not referenced by an existing Nginx site.
tixa_find_available_port() {
  local registry="$1" candidate attempt
  for attempt in $(seq 1 100); do
    candidate="$(shuf -i 10000-19999 -n 1)"

    if [ -f "$registry" ] && jq -e --argjson port "$candidate" \
        'any(.[]; .port == $port)' "$registry" >/dev/null 2>&1; then
      continue
    fi
    if tixa_port_in_use "$candidate"; then
      continue
    fi
    if grep -Rqs "127\.0\.0\.1:${candidate}\b" /etc/nginx/sites-available 2>/dev/null; then
      continue
    fi

    printf '%s' "$candidate"
    return 0
  done
  return 1
}

# Replace the registry through a temp file on the same filesystem. Writing via a
# predictable /tmp path let any local user pre-create a symlink and redirect a
# root-owned write.
tixa_commit_registry() {
  local registry="$1" content_file="$2"
  mv -f "$content_file" "$registry"
  chmod 600 "$registry"
}

# Install the shared rate-limit zones referenced by every generated site.
tixa_install_nginx_limits() {
  local base_dir="$1"
  local source="$base_dir/templates/limits.conf.tpl"
  local target="/etc/nginx/conf.d/tixa-limits.conf"

  [ -f "$source" ] || return 0
  if [ -f "$target" ] && cmp -s "$source" "$target"; then
    return 0
  fi
  install -m 644 "$source" "$target"
}

# Explain why certbot failed instead of always blaming rate limiting.
tixa_describe_certbot_failure() {
  local log="$1"

  if grep -qiE 'too many certificates|rateLimited|rate limit' "$log" 2>/dev/null; then
    echo "Let's Encrypt rate limit reached for this domain."
  elif grep -qiE 'NXDOMAIN|DNS problem|no valid A records' "$log" 2>/dev/null; then
    echo "Let's Encrypt could not resolve the domain (DNS problem)."
  elif grep -qiE 'Timeout during connect|Connection refused|connection' "$log" 2>/dev/null; then
    echo "Let's Encrypt could not reach this server on port 80 (firewall or DNS)."
  elif grep -qiE 'unauthorized|incorrect validation certificate' "$log" 2>/dev/null; then
    echo "The HTTP-01 challenge was served by a different host."
  else
    echo "Certbot failed. Last lines of its output:"
    tail -n 15 "$log" 2>/dev/null | sed 's/^/    /'
  fi
}
