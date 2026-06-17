#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="amnezia-panel"
LEGACY_CONTAINER_NAME="vpn-panel"

echo "[1/2] Stopping container..."

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
docker rm -f "$LEGACY_CONTAINER_NAME" 2>/dev/null || true

echo "[2/2] Removing image..."

docker rmi ghcr.io/rblashchuk/amnezia-panel:latest 2>/dev/null || true
docker rmi ghcr.io/rblashchuk/amnezia-panel-collector:latest 2>/dev/null || true
docker rmi ghcr.io/rblashchuk/vpn-panel:latest 2>/dev/null || true

echo ""
echo "amnezia-panel removed"
