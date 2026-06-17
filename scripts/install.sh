#!/usr/bin/env bash
set -euo pipefail

REPO_IMAGE="ghcr.io/rblashchuk/amnezia-panel:latest"
CONTAINER_NAME="amnezia-panel"
LEGACY_CONTAINER_NAME="vpn-panel"
DATA_ROOT="/opt/amnezia-panel"
DATA_DIR="$DATA_ROOT/data"
LEGACY_DATA_DIR="/opt/vpn-panel/data"
VPN_SOURCE="${VPN_SOURCE:-docker}"
VPN_CONTAINER="${VPN_CONTAINER:-amnezia-wireguard}"
VPN_ENDPOINTS="${VPN_ENDPOINTS:-}"
PANEL_PORT="${PANEL_PORT:-9000}"
VPN_PANEL_MODE="${VPN_PANEL_MODE:-collector}"
VPN_REMOTE_URL="${VPN_REMOTE_URL:-}"
VPN_REMOTE_TOKEN="${VPN_REMOTE_TOKEN:-}"
VPN_PANEL_TOKEN="${VPN_PANEL_TOKEN:-}"

echo "[1/6] Checking environment..."

case "$VPN_PANEL_MODE" in
  collector|local-proxy)
    ;;
  *)
    echo "ERROR: unsupported VPN_PANEL_MODE=$VPN_PANEL_MODE (use collector or local-proxy)"
    exit 1
    ;;
esac

if [ "$VPN_PANEL_MODE" = "local-proxy" ] && [ -z "$VPN_REMOTE_URL" ]; then
  echo "ERROR: VPN_REMOTE_URL is required in local-proxy mode"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not installed"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: docker daemon not accessible (run as root or fix docker group)"
  exit 1
fi

if [ "$VPN_PANEL_MODE" = "local-proxy" ]; then
  echo "[2/6] Creating data directory..."

  mkdir -p "$DATA_DIR"
  chmod 755 "$DATA_DIR"

  echo "[3/6] Pulling image..."

  docker pull "$REPO_IMAGE"

  echo "[4/6] Stopping old container..."

  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
  docker rm -f "$LEGACY_CONTAINER_NAME" 2>/dev/null || true

  echo "[5/6] Starting local proxy container..."

  docker_args=(
    -d
    --name "$CONTAINER_NAME"
    --restart unless-stopped
    --add-host host.docker.internal:host-gateway
    -p "127.0.0.1:${PANEL_PORT}:9000"
    -v "$DATA_DIR:/app/data"
    -e VPN_PANEL_LISTEN=0.0.0.0:9000
    -e "VPN_REMOTE_URL=$VPN_REMOTE_URL"
  )

  if [ -n "$VPN_REMOTE_TOKEN" ]; then
    docker_args+=(-e "VPN_REMOTE_TOKEN=$VPN_REMOTE_TOKEN")
  fi

  docker run "${docker_args[@]}" "$REPO_IMAGE"

  echo "[6/6] Verifying..."

  sleep 1

  if docker ps | grep -q "$CONTAINER_NAME"; then
    echo "OK: amnezia-panel running"
  else
    echo "ERROR: container failed to start"
    docker logs "$CONTAINER_NAME" || true
    exit 1
  fi

  echo ""
  echo "OK: amnezia-panel running in local proxy mode"
  echo "Remote: $VPN_REMOTE_URL"
  echo "Access: http://127.0.0.1:${PANEL_PORT}"
  exit 0
fi

echo "[2/6] Creating data directory..."

if [ ! -d "$DATA_DIR" ] && [ -d "$LEGACY_DATA_DIR" ]; then
  echo "Migrating data from $LEGACY_DATA_DIR to $DATA_DIR..."
  mkdir -p "$DATA_ROOT"
  mv "$LEGACY_DATA_DIR" "$DATA_DIR"
fi

mkdir -p "$DATA_DIR"
chmod 755 "$DATA_DIR"

echo "[3/6] Pulling image..."

docker pull "$REPO_IMAGE"

if [ "$VPN_SOURCE" = "docker" ] && [ -z "$VPN_ENDPOINTS" ]; then
  echo "Discovering Amnezia containers..."

  endpoints=()

  if docker ps -a --format '{{.Names}}' | grep -Fxq "amnezia-awg2"; then
    endpoints+=("awg:amnezia-awg2:awg")
  fi

  if docker ps -a --format '{{.Names}}' | grep -Fxq "amnezia-wireguard"; then
    endpoints+=("wireguard:amnezia-wireguard:wg")
  fi

  if [ "${#endpoints[@]}" -eq 0 ]; then
    echo "ERROR: no supported Amnezia containers found"
    echo "Supported containers: amnezia-awg2, amnezia-wireguard"
    exit 1
  fi

  VPN_ENDPOINTS="$(IFS=,; echo "${endpoints[*]}")"
  echo "Found sources: $VPN_ENDPOINTS"
fi

echo "[4/6] Stopping old container..."

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
docker rm -f "$LEGACY_CONTAINER_NAME" 2>/dev/null || true

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
      -e "VPN_ENDPOINTS=$VPN_ENDPOINTS" \
      -e VPN_PANEL_LISTEN=0.0.0.0:9000 \
      ${VPN_PANEL_TOKEN:+-e VPN_PANEL_TOKEN="$VPN_PANEL_TOKEN"} \
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
      ${VPN_PANEL_TOKEN:+-e VPN_PANEL_TOKEN="$VPN_PANEL_TOKEN"} \
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
  echo "OK: amnezia-panel running"
else
  echo "ERROR: container failed to start"
  docker logs "$CONTAINER_NAME" || true
  exit 1
fi

echo ""
echo "OK: amnezia-panel running in docker"
echo "Mode: $VPN_SOURCE"
if [ -n "$VPN_PANEL_TOKEN" ]; then
  echo "API token: enabled"
fi
if [ -n "$VPN_ENDPOINTS" ]; then
  echo "Sources: $VPN_ENDPOINTS"
fi
echo "Access: http://127.0.0.1:${PANEL_PORT} (via SSH tunnel if needed)"
