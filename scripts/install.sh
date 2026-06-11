#!/usr/bin/env bash
set -euo pipefail

REPO="rblashchuk/vpn-panel"
INSTALL_DIR="/opt/vpn-panel"
BRANCH="master"

echo "[1/5] Checking environment..."

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin is not installed"
  exit 1
fi

echo "[2/5] Creating install dir..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "[3/5] Downloading compose + env..."

curl -fsSL \
  "https://raw.githubusercontent.com/$REPO/$BRANCH/docker-compose.yml" \
  -o docker-compose.yml

curl -fsSL \
  "https://raw.githubusercontent.com/$REPO/$BRANCH/.env.example" \
  -o .env || true

echo "[4/5] Pulling image..."
docker compose pull

echo "[5/5] Starting..."
docker compose up -d

echo ""
echo "OK: vpn-panel installed"
echo "Access: ssh -L 9000:127.0.0.1:9000 user@server"