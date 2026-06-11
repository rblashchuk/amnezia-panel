#!/usr/bin/env bash
set -euo pipefail

REPO_IMAGE="ghcr.io/rblashchuk/vpn-panel:latest"
SERVICE="vpn-panel"
CONTAINER_NAME="vpn-panel"

echo "[1/5] Checking environment..."

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not installed"
  exit 1
fi

echo "[2/5] Pulling image..."

docker pull "$REPO_IMAGE"

echo "[3/5] Stopping old container..."

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "[4/5] Starting container..."

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p 9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  "$REPO_IMAGE"

echo "[5/5] Done"

echo ""
echo "OK: vpn-panel running in docker"
echo "Access: http://127.0.0.1:9000 (via SSH tunnel if needed)"