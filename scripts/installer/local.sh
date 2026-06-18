#!/usr/bin/env bash

detect_image_update() {
  local_pull_args=()
  if [ -n "$LOCAL_DOCKER_PLATFORM" ]; then
    warn "Local Docker platform override: $LOCAL_DOCKER_PLATFORM"
    local_pull_args+=(--platform "$LOCAL_DOCKER_PLATFORM")
  fi

  local current_container_image=""
  if docker ps -a --format '{{.Names}}' | grep -Fxq "$LOCAL_CONTAINER_NAME"; then
    current_container_image="$(docker inspect -f '{{.Image}}' "$LOCAL_CONTAINER_NAME")"
  fi

  docker pull "${local_pull_args[@]}" "$REPO_IMAGE"

  local latest_image
  latest_image="$(docker image inspect -f '{{.Id}}' "$REPO_IMAGE")"

  if [ -n "$current_container_image" ] && [ "$current_container_image" != "$latest_image" ]; then
    APPLY_IMAGE_UPDATE=""
    ask_yes_no APPLY_IMAGE_UPDATE "A newer Amnezia Panel image is available. Update local panel and VPS collector?" "y"
    if [ "$APPLY_IMAGE_UPDATE" = "yes" ]; then
      LOCAL_IMAGE_TO_RUN="$REPO_IMAGE"
      REMOTE_UPDATE_MODE="update"
    else
      LOCAL_IMAGE_TO_RUN="$current_container_image"
      REMOTE_UPDATE_MODE="skip"
      warn "Keeping the currently installed image."
    fi
  else
    LOCAL_IMAGE_TO_RUN="$REPO_IMAGE"
    REMOTE_UPDATE_MODE="install"
  fi
}

start_ssh_tunnel() {
  mkdir -p "$DATA_ROOT"
  chmod 755 "$DATA_ROOT"

  CONTROL_SOCKET="$DATA_ROOT/ssh-tunnel.sock"
  if [ -e "$CONTROL_SOCKET" ]; then
    "${SSH_CMD[@]}" "${SSH_ARGS[@]}" -S "$CONTROL_SOCKET" -O exit "$SSH_TARGET" >/dev/null 2>&1 || true
    rm -f "$CONTROL_SOCKET"
  fi

  "${SSH_CMD[@]}" "${SSH_ARGS[@]}" \
    -M -S "$CONTROL_SOCKET" \
    -fN \
    -L "127.0.0.1:${LOCAL_TUNNEL_PORT}:127.0.0.1:${REMOTE_COLLECTOR_PORT}" \
    "$SSH_TARGET"
}

install_local_panel() {
  mkdir -p "$DATA_DIR"
  chmod 755 "$DATA_DIR"

  local_run_args=()
  local_docker_socket_args=()
  local_ssh_args=()
  container_vps_ssh_key="$VPS_SSH_KEY"
  if [ -n "$LOCAL_DOCKER_PLATFORM" ]; then
    local_run_args+=(--platform "$LOCAL_DOCKER_PLATFORM")
  fi
  detect_local_docker_socket
  if [ -n "${LOCAL_DOCKER_SOCKET:-}" ]; then
    local_docker_socket_args+=(-v "$LOCAL_DOCKER_SOCKET:/var/run/docker.sock")
  fi
  prepare_local_ssh_mounts

  docker rm -f "$LOCAL_CONTAINER_NAME" 2>/dev/null || true

  docker run -d \
    "${local_run_args[@]}" \
    "${local_docker_socket_args[@]}" \
    "${local_ssh_args[@]}" \
    --name "$LOCAL_CONTAINER_NAME" \
    --restart unless-stopped \
    --label "amnezia.panel.profile=$PROFILE_NAME" \
    --add-host host.docker.internal:host-gateway \
    -p "127.0.0.1:${LOCAL_PANEL_PORT}:9000" \
    -v "$DATA_DIR:/app/data" \
    -e VPN_PANEL_LISTEN=0.0.0.0:9000 \
    -e "VPN_REMOTE_URL=http://host.docker.internal:${LOCAL_TUNNEL_PORT}" \
    -e "VPN_REMOTE_TOKEN=$VPN_PANEL_TOKEN" \
    -e "PANEL_IMAGE=$PANEL_IMAGE" \
    -e "COLLECTOR_IMAGE=$COLLECTOR_IMAGE" \
    -e "LOCAL_DOCKER_PLATFORM=$LOCAL_DOCKER_PLATFORM" \
    -e "LOCAL_CONTAINER_NAME=$LOCAL_CONTAINER_NAME" \
    -e "REMOTE_CONTAINER_NAME=$REMOTE_CONTAINER_NAME" \
    -e "VPS_AUTH_METHOD=$VPS_AUTH_METHOD" \
    -e "VPS_HOST=$VPS_HOST" \
    -e "VPS_USER=$VPS_USER" \
    -e "VPS_PORT=$VPS_PORT" \
    -e "VPS_SSH_KEY=$container_vps_ssh_key" \
    "$LOCAL_IMAGE_TO_RUN"
}

prepare_local_ssh_mounts() {
  if [ -d "$HOME/.ssh" ]; then
    local_ssh_args+=(-v "$HOME/.ssh:/root/.ssh:ro")
  fi

  if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    local_ssh_args+=(-v "$SSH_AUTH_SOCK:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent)
  fi

  if [ "$VPS_AUTH_METHOD" = "identity-file" ] && [ -n "$VPS_SSH_KEY" ]; then
    case "$VPS_SSH_KEY" in
      "$HOME/.ssh/"*)
        container_vps_ssh_key="/root/.ssh/${VPS_SSH_KEY#"$HOME/.ssh/"}"
        ;;
      *)
        local key_dir
        key_dir="$(dirname "$VPS_SSH_KEY")"
        local_ssh_args+=(-v "$key_dir:$key_dir:ro")
        ;;
    esac
  fi
}

detect_local_docker_socket() {
  LOCAL_DOCKER_SOCKET=""
  LOCAL_DOCKER_SOCKET_DAEMON_SIDE=""

  case "${DOCKER_HOST:-}" in
    unix://*/.colima/*/docker.sock)
      LOCAL_DOCKER_SOCKET="/var/run/docker.sock"
      LOCAL_DOCKER_SOCKET_DAEMON_SIDE="yes"
      ;;
    unix://*)
      LOCAL_DOCKER_SOCKET="${DOCKER_HOST#unix://}"
      ;;
  esac

  if [ -z "$LOCAL_DOCKER_SOCKET" ] && [ -S /var/run/docker.sock ]; then
    LOCAL_DOCKER_SOCKET="/var/run/docker.sock"
  fi

  if [ -z "$LOCAL_DOCKER_SOCKET" ] && command -v docker >/dev/null 2>&1; then
    local docker_host
    docker_host="$(docker context inspect --format '{{ .Endpoints.docker.Host }}' 2>/dev/null || true)"
    case "$docker_host" in
      unix://*/.colima/*/docker.sock)
        LOCAL_DOCKER_SOCKET="/var/run/docker.sock"
        LOCAL_DOCKER_SOCKET_DAEMON_SIDE="yes"
        ;;
      unix://*) LOCAL_DOCKER_SOCKET="${docker_host#unix://}" ;;
    esac
  fi

  if [ -n "$LOCAL_DOCKER_SOCKET" ] && [ "$LOCAL_DOCKER_SOCKET_DAEMON_SIDE" != "yes" ] && [ ! -S "$LOCAL_DOCKER_SOCKET" ]; then
    warn "Docker socket not found at $LOCAL_DOCKER_SOCKET; update checks from UI will be unavailable."
    LOCAL_DOCKER_SOCKET=""
  fi
}

verify_local_panel() {
  sleep 1

  if ! docker ps --format '{{.Names}}' | grep -Fxq "$LOCAL_CONTAINER_NAME"; then
    echo "ERROR: local panel container failed to start"
    docker logs "$LOCAL_CONTAINER_NAME" || true
    exit 1
  fi
}
