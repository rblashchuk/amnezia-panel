#!/usr/bin/env bash
set -euo pipefail

REPO_IMAGE="ghcr.io/rblashchuk/vpn-panel:latest"
SERVICE="vpn-panel"
CONTAINER_NAME="vpn-panel"
DATA_DIR="/opt/vpn-panel/data"

echo "[1/6] Checking environment..."

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not installed"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: docker daemon not accessible (run as root or fix docker group)"
  exit 1
fi

echo "[2/6] Creating data directory..."

mkdir -p "$DATA_DIR"
chmod 755 "$DATA_DIR"

echo "[3/6] Pulling image..."

docker pull "$REPO_IMAGE"

echo "[4/6] Stopping old container..."

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "[5/6] Starting container..."

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p 9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$DATA_DIR:/app/data" \
  "$REPO_IMAGE"

echo "[6/6] Verifying..."

sleep 1

if docker ps | grep -q "$CONTAINER_NAME"; then
  echo "OK: vpn-panel running"
else
  echo "ERROR: container failed to start"
  docker logs "$CONTAINER_NAME" || true
  exit 1
fi

echo ""
echo "OK: vpn-panel running in docker"
echo "Access: http://127.0.0.1:9000 (via SSH tunnel if needed)"