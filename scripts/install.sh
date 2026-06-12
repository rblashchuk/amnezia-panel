#!/usr/bin/env bash
set -euo pipefail

REPO_IMAGE="ghcr.io/rblashchuk/vpn-panel:latest"
CONTAINER_NAME="vpn-panel"
DATA_DIR="/opt/vpn-panel/data"
VPN_SOURCE="${VPN_SOURCE:-docker}"
VPN_CONTAINER="${VPN_CONTAINER:-amnezia-wireguard}"
PANEL_PORT="${PANEL_PORT:-9000}"

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

case "$VPN_SOURCE" in
  docker)
    docker run -d \
      --name "$CONTAINER_NAME" \
      --restart unless-stopped \
      -p "127.0.0.1:${PANEL_PORT}:9000" \
      -v /var/run/docker.sock:/var/run/docker.sock:ro \
      -v "$DATA_DIR:/app/data" \
      -e VPN_SOURCE=docker \
      -e "VPN_CONTAINER=$VPN_CONTAINER" \
      -e VPN_PANEL_LISTEN=0.0.0.0:9000 \
      "$REPO_IMAGE"
    ;;
  local)
    docker run -d \
      --name "$CONTAINER_NAME" \
      --restart unless-stopped \
      --network host \
      --cap-add NET_ADMIN \
      -v "$DATA_DIR:/app/data" \
      -e VPN_SOURCE=local \
      -e VPN_PANEL_LISTEN="127.0.0.1:${PANEL_PORT}" \
      "$REPO_IMAGE"
    ;;
  *)
    echo "ERROR: unsupported VPN_SOURCE=$VPN_SOURCE (use docker or local)"
    exit 1
    ;;
esac

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
echo "Mode: $VPN_SOURCE"
echo "Access: http://127.0.0.1:${PANEL_PORT} (via SSH tunnel if needed)"
