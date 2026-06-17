#!/usr/bin/env bash

write_profile_value() {
  local key="$1"
  local value="$2"
  printf '%s=' "$key" >> "$PROFILE_PATH"
  printf '%q\n' "$value" >> "$PROFILE_PATH"
}

save_profile() {
  mkdir -p "$DATA_ROOT"
  umask 077
  : > "$PROFILE_PATH"

  write_profile_value REPO_IMAGE "$REPO_IMAGE"
  write_profile_value LOCAL_CONTAINER_NAME "$LOCAL_CONTAINER_NAME"
  write_profile_value REMOTE_CONTAINER_NAME "$REMOTE_CONTAINER_NAME"
  write_profile_value DATA_ROOT "$DATA_ROOT"
  write_profile_value DATA_DIR "$DATA_DIR"
  write_profile_value LOCAL_PANEL_PORT "$LOCAL_PANEL_PORT"
  write_profile_value LOCAL_TUNNEL_PORT "$LOCAL_TUNNEL_PORT"
  write_profile_value REMOTE_COLLECTOR_PORT "$REMOTE_COLLECTOR_PORT"
  write_profile_value LOCAL_DOCKER_PLATFORM "$LOCAL_DOCKER_PLATFORM"
  write_profile_value VPN_PANEL_TOKEN "$VPN_PANEL_TOKEN"
  write_profile_value VPS_AUTH_METHOD "$VPS_AUTH_METHOD"
  write_profile_value VPS_HOST "$VPS_HOST"
  write_profile_value VPS_USER "$VPS_USER"
  write_profile_value VPS_PORT "$VPS_PORT"
  write_profile_value VPS_SSH_KEY "$VPS_SSH_KEY"
}

install_cli() {
  mkdir -p "$BIN_DIR"
  cat > "$CLI_PATH" <<'CLI_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

DATA_ROOT="${AMNEZIA_PANEL_HOME:-$HOME/.amnezia-panel}"
PROFILE_PATH="$DATA_ROOT/profile.env"

if [ ! -f "$PROFILE_PATH" ]; then
  echo "ERROR: profile not found: $PROFILE_PATH" >&2
  echo "Run the installer first." >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$PROFILE_PATH"

SSH_TARGET="$VPS_HOST"
SSH_CMD=(ssh)
SSH_ARGS=(-o ServerAliveInterval=30 -o ServerAliveCountMax=3)

if [ "$VPS_AUTH_METHOD" != "ssh-config" ]; then
  SSH_TARGET="${VPS_USER}@${VPS_HOST}"
  SSH_ARGS=(-p "$VPS_PORT" "${SSH_ARGS[@]}")
fi

if [ "$VPS_AUTH_METHOD" = "identity-file" ]; then
  SSH_ARGS+=(-i "$VPS_SSH_KEY")
elif [ "$VPS_AUTH_METHOD" = "password-only" ]; then
  SSH_ARGS+=(-o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no)
fi

CONTROL_SOCKET="$DATA_ROOT/ssh-tunnel.sock"
mkdir -p "$DATA_ROOT"

if [ -e "$CONTROL_SOCKET" ]; then
  "${SSH_CMD[@]}" "${SSH_ARGS[@]}" -S "$CONTROL_SOCKET" -O check "$SSH_TARGET" >/dev/null 2>&1 || rm -f "$CONTROL_SOCKET"
fi

if [ ! -e "$CONTROL_SOCKET" ]; then
  "${SSH_CMD[@]}" "${SSH_ARGS[@]}" \
    -M -S "$CONTROL_SOCKET" \
    -fN \
    -L "127.0.0.1:${LOCAL_TUNNEL_PORT}:127.0.0.1:${REMOTE_COLLECTOR_PORT}" \
    "$SSH_TARGET"
fi

if docker ps --format '{{.Names}}' | grep -Fxq "$LOCAL_CONTAINER_NAME"; then
  :
elif docker ps -a --format '{{.Names}}' | grep -Fxq "$LOCAL_CONTAINER_NAME"; then
  docker start "$LOCAL_CONTAINER_NAME" >/dev/null
else
  local_run_args=()
  if [ -n "${LOCAL_DOCKER_PLATFORM:-}" ]; then
    local_run_args+=(--platform "$LOCAL_DOCKER_PLATFORM")
  fi

  docker run -d \
    "${local_run_args[@]}" \
    --name "$LOCAL_CONTAINER_NAME" \
    --restart unless-stopped \
    --add-host host.docker.internal:host-gateway \
    -p "127.0.0.1:${LOCAL_PANEL_PORT}:9000" \
    -v "$DATA_DIR:/app/data" \
    -e VPN_PANEL_LISTEN=0.0.0.0:9000 \
    -e "VPN_REMOTE_URL=http://host.docker.internal:${LOCAL_TUNNEL_PORT}" \
    -e "VPN_REMOTE_TOKEN=$VPN_PANEL_TOKEN" \
    "$REPO_IMAGE" >/dev/null
fi

echo "Amnezia Panel is running:"
echo "http://127.0.0.1:${LOCAL_PANEL_PORT}"
CLI_SCRIPT

  chmod 700 "$CLI_PATH"
}
