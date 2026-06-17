#!/usr/bin/env bash

install_remote_collector() {
  local remote_env=(
    "REPO_IMAGE=$REPO_IMAGE"
    "COLLECTOR_IMAGE=$COLLECTOR_IMAGE"
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

remote_info() {
  echo "REMOTE: $*"
}

run_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

run_sudo_timeout() {
  local seconds="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    run_sudo timeout "$seconds" "$@"
  else
    run_sudo "$@"
  fi
}

ensure_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    remote_info "running as root"
    return
  fi

  remote_info "checking sudo access"
  sudo -v
  remote_info "sudo access granted"
}

install_docker_if_needed() {
  if command -v docker >/dev/null 2>&1; then
    remote_info "Docker CLI found"
    return
  fi

  remote_info "Docker is not installed on VPS, trying to install it"

  if command -v apt-get >/dev/null 2>&1; then
    remote_info "installing Docker with apt-get"
    run_sudo apt-get update
    run_sudo apt-get install -y docker.io
  elif command -v dnf >/dev/null 2>&1; then
    remote_info "installing Docker with dnf"
    run_sudo dnf install -y docker
  elif command -v yum >/dev/null 2>&1; then
    remote_info "installing Docker with yum"
    run_sudo yum install -y docker
  else
    echo "ERROR: unsupported package manager, install Docker manually on VPS"
    exit 1
  fi

  if command -v systemctl >/dev/null 2>&1; then
    remote_info "starting Docker service"
    run_sudo systemctl enable --now docker || run_sudo systemctl start docker
  fi
}

ensure_sudo
install_docker_if_needed

remote_info "checking Docker daemon"
if ! run_sudo_timeout 30 docker info >/dev/null 2>&1; then
  echo "ERROR: docker daemon not accessible on VPS"
  exit 1
fi

remote_info "preparing data directory: $REMOTE_DATA_DIR"
run_sudo mkdir -p "$REMOTE_DATA_DIR"
run_sudo chmod 755 "$REMOTE_DATA_DIR"

cleanup_panel_images() {
  remote_info "cleaning unused old panel images"
  run_sudo docker image prune -f >/dev/null 2>&1 || true
  for image in \
    ghcr.io/rblashchuk/amnezia-panel \
    ghcr.io/rblashchuk/amnezia-panel-collector \
    ghcr.io/rblashchuk/vpn-panel; do
    run_sudo docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' \
      | awk -v repo="$image" '$1 ~ "^" repo ":" { print $2 }' \
      | sort -u \
      | while IFS= read -r image_id; do
          [ -n "$image_id" ] || continue
          run_sudo docker rmi "$image_id" >/dev/null 2>&1 || true
        done
  done
}

image_to_run="$COLLECTOR_IMAGE"
remote_info "checking existing collector container"
if run_sudo docker ps -a --format '{{.Names}}' | grep -Fxq "$REMOTE_CONTAINER_NAME"; then
  current_image_id="$(run_sudo docker inspect -f '{{.Image}}' "$REMOTE_CONTAINER_NAME")"
  if [ "$REMOTE_UPDATE_MODE" = "skip" ]; then
    remote_info "keeping current collector image"
    image_to_run="$current_image_id"
  else
    remote_info "removing current collector before image cleanup"
    run_sudo docker rm -f "$REMOTE_CONTAINER_NAME" 2>/dev/null || true
    run_sudo docker rm -f "$REMOTE_OLD_CONTAINER_NAME" 2>/dev/null || true
    run_sudo docker rm -f "$LEGACY_CONTAINER_NAME" 2>/dev/null || true
    cleanup_panel_images
    remote_info "pulling collector image: $COLLECTOR_IMAGE"
    run_sudo docker pull "$COLLECTOR_IMAGE"
  fi
else
  run_sudo docker rm -f "$REMOTE_OLD_CONTAINER_NAME" 2>/dev/null || true
  run_sudo docker rm -f "$LEGACY_CONTAINER_NAME" 2>/dev/null || true
  cleanup_panel_images
  remote_info "pulling collector image: $COLLECTOR_IMAGE"
  run_sudo docker pull "$COLLECTOR_IMAGE"
fi

if [ "$VPN_SOURCE" = "docker" ] && [ -z "$VPN_ENDPOINTS" ]; then
  remote_info "discovering Amnezia containers"
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

remote_info "removing old collector containers"
run_sudo docker rm -f "$REMOTE_CONTAINER_NAME" 2>/dev/null || true
run_sudo docker rm -f "$REMOTE_OLD_CONTAINER_NAME" 2>/dev/null || true
run_sudo docker rm -f "$LEGACY_CONTAINER_NAME" 2>/dev/null || true

remote_info "checking collector port: 127.0.0.1:${REMOTE_COLLECTOR_PORT}"
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

remote_info "starting collector container"
run_sudo docker run "${docker_args[@]}" "$image_to_run"

sleep 1

remote_info "verifying collector container"
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
