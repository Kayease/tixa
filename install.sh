#!/usr/bin/env bash
set -e

echo "======================================"
echo " TIXA MEDIA PLATFORM INSTALLER"
echo "======================================"

if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root"
  exit 1
fi

read -rp "Enter email for SSL notifications (one-time): " CERT_EMAIL
if [[ -z "$CERT_EMAIL" ]]; then
  echo "❌ Email is required"
  exit 1
fi

echo "▶ Updating system..."
apt update -y

echo "▶ Installing system dependencies..."
apt install -y \
  nginx \
  certbot \
  python3-certbot-nginx \
  python3 \
  python3-venv \
  ffmpeg \
  libvips \
  jq \
  curl \
  git

echo "▶ Enabling nginx..."
systemctl enable nginx
systemctl start nginx

echo "▶ Registering certbot account (one-time)..."
certbot register \
  --agree-tos \
  -m "$CERT_EMAIL" \
  --no-eff-email || true

echo "▶ Installing Tixa core..."
mkdir -p /opt/tixa
cp -r "$(pwd)/core" /opt/tixa/

mkdir -p /opt/tixa/registry
[[ ! -f /opt/tixa/registry/services.json ]] && echo "{}" > /opt/tixa/registry/services.json

chmod +x /opt/tixa/core/core.sh || true

echo "▶ Installing Tixa CLI..."
cp "$(pwd)/cli/tixa" /usr/local/bin/tixa
chmod +x /usr/local/bin/tixa

echo "▶ Writing version..."
echo "1.0.0" > /opt/tixa/version

echo ""
echo "✅ TIXA INSTALLED SUCCESSFULLY"
echo "--------------------------------------"
echo "Next step:"
echo "  tixa create"
echo "--------------------------------------"
