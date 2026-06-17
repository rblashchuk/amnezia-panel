#!/usr/bin/env bash

install_remote_collector() {
  local remote_env=(
    "REPO_IMAGE=$REPO_IMAGE"
    "REMOTE_CONTAINER_NAME=$REMOTE_CONTAINER_NAME"
    "REMOTE_OLD_CONTAINER_NAME=$REMOTE_OLD_CONTAINER_NAME"
    "LEGACY_CONTAINER_NAME=$LEGACY_CONTAINER_NAME"
    "REMOTE_DATA_ROOT=$REMOTE_DATA_ROOT"
    "REMOTE_DATA_DIR=$REMOTE_DATA_DIR"
    "REMOTE_COLLECTOR_PORT=$REMOTE_COLLECTOR_PORT"
    "VPN_SOURCE=$VPN_SOURCE"
    "VPN_ENDPOINTS=$VPN_ENDPOINTS"
    "VPN_PANEL_TOKEN=$VPN_PANEL_TOKEN"
    "REMOTE_UPDATE_MODE=$REMOTE_UPDATE_MODE"
  )

  local remote_script_path="/tmp/amnezia-panel-install-$$.sh"

  "${SSH_CMD[@]}" "${SSH_ARGS[@]}" "$SSH_TARGET" "cat > '$remote_script_path' && chmod 700 '$remote_script_path'" <<'REMOTE_SCRIPT'
set -euo pipefail

run_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

install_docker_if_needed() {
  if command -v docker >/dev/null 2>&1; then
    return
  fi

  echo "Docker is not installed on VPS, trying to install it..."

  if command -v apt-get >/dev/null 2>&1; then
    run_sudo apt-get update
    run_sudo apt-get install -y docker.io
  elif command -v dnf >/dev/null 2>&1; then
    run_sudo dnf install -y docker
  elif command -v yum >/dev/null 2>&1; then
    run_sudo yum install -y docker
  else
    echo "ERROR: unsupported package manager, install Docker manually on VPS"
    exit 1
  fi

  if command -v systemctl >/dev/null 2>&1; then
    run_sudo systemctl enable --now docker || run_sudo systemctl start docker
  fi
}

install_docker_if_needed

if ! run_sudo docker info >/dev/null 2>&1; then
  echo "ERROR: docker daemon not accessible on VPS"
  exit 1
fi

run_sudo mkdir -p "$REMOTE_DATA_DIR"
run_sudo chmod 755 "$REMOTE_DATA_DIR"

image_to_run="$REPO_IMAGE"
if run_sudo docker ps -a --format '{{.Names}}' | grep -Fxq "$REMOTE_CONTAINER_NAME"; then
  current_image_id="$(run_sudo docker inspect -f '{{.Image}}' "$REMOTE_CONTAINER_NAME")"
  if [ "$REMOTE_UPDATE_MODE" = "skip" ]; then
    image_to_run="$current_image_id"
  else
    run_sudo docker pull "$REPO_IMAGE"
  fi
else
  run_sudo docker pull "$REPO_IMAGE"
fi

if [ "$VPN_SOURCE" = "docker" ] && [ -z "$VPN_ENDPOINTS" ]; then
  endpoints=()

  if run_sudo docker ps -a --format '{{.Names}}' | grep -Fxq "amnezia-awg2"; then
    endpoints+=("awg:amnezia-awg2:awg")
  fi

  if run_sudo docker ps -a --format '{{.Names}}' | grep -Fxq "amnezia-wireguard"; then
    endpoints+=("wireguard:amnezia-wireguard:wg")
  fi

  if [ "${#endpoints[@]}" -eq 0 ]; then
    echo "ERROR: no supported Amnezia containers found on VPS"
    echo "Supported containers: amnezia-awg2, amnezia-wireguard"
    exit 1
  fi

  VPN_ENDPOINTS="$(IFS=,; echo "${endpoints[*]}")"
fi

run_sudo docker rm -f "$REMOTE_CONTAINER_NAME" 2>/dev/null || true
run_sudo docker rm -f "$REMOTE_OLD_CONTAINER_NAME" 2>/dev/null || true
run_sudo docker rm -f "$LEGACY_CONTAINER_NAME" 2>/dev/null || true

if run_sudo docker ps --format '{{.Names}}\t{{.Ports}}' | grep -q "127.0.0.1:${REMOTE_COLLECTOR_PORT}->"; then
  echo "ERROR: 127.0.0.1:${REMOTE_COLLECTOR_PORT} is already used by another Docker container"
  run_sudo docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep "127.0.0.1:${REMOTE_COLLECTOR_PORT}->" || true
  exit 1
fi

docker_args=(
  -d
  --name "$REMOTE_CONTAINER_NAME"
  --restart unless-stopped
  -p "127.0.0.1:${REMOTE_COLLECTOR_PORT}:9000"
  -v /var/run/docker.sock:/var/run/docker.sock:ro
  -v "$REMOTE_DATA_DIR:/app/data"
  -e VPN_SOURCE=docker
  -e "VPN_ENDPOINTS=$VPN_ENDPOINTS"
  -e VPN_PANEL_LISTEN=0.0.0.0:9000
  -e "VPN_PANEL_TOKEN=$VPN_PANEL_TOKEN"
)

run_sudo docker run "${docker_args[@]}" "$image_to_run"

sleep 1

if ! run_sudo docker ps --format '{{.Names}}' | grep -Fxq "$REMOTE_CONTAINER_NAME"; then
  echo "ERROR: collector container failed to start on VPS"
  run_sudo docker logs "$REMOTE_CONTAINER_NAME" || true
  exit 1
fi

echo "VPS collector installed"
echo "Sources: $VPN_ENDPOINTS"
REMOTE_SCRIPT

  "${SSH_CMD[@]}" -tt "${SSH_ARGS[@]}" "$SSH_TARGET" "$(printf '%q ' "${remote_env[@]}") bash '$remote_script_path'; status=\$?; rm -f '$remote_script_path'; exit \$status"
}
