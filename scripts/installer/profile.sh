#!/usr/bin/env bash

write_profile_value() {
  local key="$1"
  local value="$2"
  printf '%s=' "$key" >> "$PROFILE_PATH"
  printf '%q\n' "$value" >> "$PROFILE_PATH"
}

save_profile() {
  mkdir -p "$PROFILES_DIR"
  umask 077
  : > "$PROFILE_PATH"

  write_profile_value PROFILE_NAME "$PROFILE_NAME"
  write_profile_value REPO_IMAGE "$PANEL_IMAGE"
  write_profile_value PANEL_IMAGE "$PANEL_IMAGE"
  write_profile_value COLLECTOR_IMAGE "$COLLECTOR_IMAGE"
  write_profile_value LOCAL_CONTAINER_NAME "$LOCAL_CONTAINER_NAME"
  write_profile_value REMOTE_CONTAINER_NAME "$REMOTE_CONTAINER_NAME"
  write_profile_value REMOTE_OLD_CONTAINER_NAME "$REMOTE_OLD_CONTAINER_NAME"
  write_profile_value LEGACY_CONTAINER_NAME "$LEGACY_CONTAINER_NAME"
  write_profile_value DATA_ROOT "$DATA_ROOT"
  write_profile_value DATA_DIR "$DATA_DIR"
  write_profile_value REMOTE_DATA_ROOT "$REMOTE_DATA_ROOT"
  write_profile_value REMOTE_DATA_DIR "$REMOTE_DATA_DIR"
  write_profile_value LOCAL_PANEL_PORT "$LOCAL_PANEL_PORT"
  write_profile_value LOCAL_TUNNEL_PORT "$LOCAL_TUNNEL_PORT"
  write_profile_value REMOTE_COLLECTOR_PORT "$REMOTE_COLLECTOR_PORT"
  write_profile_value LOCAL_DOCKER_PLATFORM "$LOCAL_DOCKER_PLATFORM"
  write_profile_value VPN_SOURCE "$VPN_SOURCE"
  write_profile_value VPN_ENDPOINTS "$VPN_ENDPOINTS"
  write_profile_value VPN_PANEL_TOKEN "$VPN_PANEL_TOKEN"
  write_profile_value VPS_AUTH_METHOD "$VPS_AUTH_METHOD"
  write_profile_value VPS_HOST "$VPS_HOST"
  write_profile_value VPS_USER "$VPS_USER"
  write_profile_value VPS_PORT "$VPS_PORT"
  write_profile_value VPS_SSH_KEY "$VPS_SSH_KEY"

  printf '%s\n' "$PROFILE_NAME" > "$CURRENT_PROFILE_PATH"
  cp "$PROFILE_PATH" "$DATA_ROOT/profile.env"
}

current_profile_name() {
  if [ -f "$CURRENT_PROFILE_PATH" ]; then
    sed -n '1p' "$CURRENT_PROFILE_PATH"
  else
    echo "default"
  fi
}

load_profile_if_exists() {
  local selected_profile_name="$PROFILE_NAME"
  local selected_profile_path="$PROFILE_PATH"

  if [ -f "$PROFILE_PATH" ]; then
    # shellcheck disable=SC1090
    . "$PROFILE_PATH"
    PROFILE_NAME="$selected_profile_name"
    PROFILE_PATH="$selected_profile_path"
    info "Loaded connection profile: $PROFILE_NAME"
    return
  fi

  if [ "$PROFILE_NAME" = "default" ] && [ -f "$DATA_ROOT/profile.env" ]; then
    # shellcheck disable=SC1090
    . "$DATA_ROOT/profile.env"
    PROFILE_NAME="default"
    PROFILE_PATH="$selected_profile_path"
    info "Loaded legacy connection profile: default"
  fi
}

install_cli() {
  mkdir -p "$BIN_DIR"
  cat > "$CLI_PATH" <<'CLI_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

DATA_ROOT="${AMNEZIA_PANEL_HOME:-$HOME/.amnezia-panel}"
PROFILES_DIR="$DATA_ROOT/profiles"
CURRENT_PROFILE_PATH="$DATA_ROOT/current-profile"
LEGACY_PROFILE_PATH="$DATA_ROOT/profile.env"

usage() {
  cat <<'USAGE'
Usage:
  amnezia-panel [--profile NAME]
  amnezia-panel --no-update-check
  amnezia-panel profiles
  amnezia-panel current
  amnezia-panel use NAME
USAGE
}

current_profile_name() {
  if [ -f "$CURRENT_PROFILE_PATH" ]; then
    sed -n '1p' "$CURRENT_PROFILE_PATH"
  else
    echo "default"
  fi
}

list_profiles() {
  if [ -d "$PROFILES_DIR" ]; then
    found=0
    for profile in "$PROFILES_DIR"/*.env; do
      [ -e "$profile" ] || continue
      found=1
      basename "$profile" .env
    done
    [ "$found" -eq 1 ] && return
  fi

  [ -f "$LEGACY_PROFILE_PATH" ] && echo "default"
}

PROFILE_NAME=""
CHECK_UPDATES="yes"

while [ "$#" -gt 0 ]; do
  case "$1" in
    profiles)
      list_profiles
      exit 0
      ;;
    current)
      current_profile_name
      exit 0
      ;;
    use)
      [ -n "${2:-}" ] || { usage >&2; exit 1; }
      PROFILE_NAME="$2"
      shift
      ;;
    --profile|-p)
      [ -n "${2:-}" ] || { usage >&2; exit 1; }
      PROFILE_NAME="$2"
      shift
      ;;
    --no-update-check)
      CHECK_UPDATES="no"
      ;;
    start)
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown command: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ -z "$PROFILE_NAME" ]; then
  PROFILE_NAME="$(current_profile_name)"
fi

PROFILE_PATH="$PROFILES_DIR/$PROFILE_NAME.env"
if [ ! -f "$PROFILE_PATH" ] && [ "$PROFILE_NAME" = "default" ] && [ -f "$LEGACY_PROFILE_PATH" ]; then
  PROFILE_PATH="$LEGACY_PROFILE_PATH"
fi

if [ ! -f "$PROFILE_PATH" ]; then
  echo "ERROR: profile not found: $PROFILE_PATH" >&2
  echo "Run the installer first or choose an existing profile with: amnezia-panel profiles" >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$PROFILE_PATH"
PROFILE_NAME="${PROFILE_NAME:-$(basename "$PROFILE_PATH" .env)}"
PANEL_IMAGE="${PANEL_IMAGE:-${REPO_IMAGE:-ghcr.io/rblashchuk/amnezia-panel:latest}}"
COLLECTOR_IMAGE="${COLLECTOR_IMAGE:-ghcr.io/rblashchuk/amnezia-panel-collector:latest}"
REPO_IMAGE="$PANEL_IMAGE"
printf '%s\n' "$PROFILE_NAME" > "$CURRENT_PROFILE_PATH"

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

ask_yes_no() {
  local prompt="$1"
  local default_value="${2:-n}"
  local answer

  if [ "$default_value" = "y" ]; then
    read -r -p "$prompt [Y/n]: " answer
    answer="${answer:-y}"
  else
    read -r -p "$prompt [y/N]: " answer
    answer="${answer:-n}"
  fi

  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

run_with_timeout() {
  local seconds="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
  else
    "$@"
  fi
}

update_remote_collector() {
  local remote_env=(
    "REPO_IMAGE=$REPO_IMAGE"
    "COLLECTOR_IMAGE=${COLLECTOR_IMAGE:-ghcr.io/rblashchuk/amnezia-panel-collector:latest}"
    "REMOTE_CONTAINER_NAME=${REMOTE_CONTAINER_NAME:-amnezia-panel-collector}"
    "REMOTE_OLD_CONTAINER_NAME=${REMOTE_OLD_CONTAINER_NAME:-amnezia-panel}"
    "LEGACY_CONTAINER_NAME=${LEGACY_CONTAINER_NAME:-vpn-panel}"
    "REMOTE_DATA_DIR=${REMOTE_DATA_DIR:-${REMOTE_DATA_ROOT:-/opt/amnezia-panel}/data}"
    "REMOTE_COLLECTOR_PORT=$REMOTE_COLLECTOR_PORT"
    "VPN_SOURCE=${VPN_SOURCE:-docker}"
    "VPN_ENDPOINTS=${VPN_ENDPOINTS:-}"
    "VPN_PANEL_TOKEN=$VPN_PANEL_TOKEN"
  )
  local remote_script_path="/tmp/amnezia-panel-cli-update-$$.sh"

  "${SSH_CMD[@]}" "${SSH_ARGS[@]}" "$SSH_TARGET" "cat > '$remote_script_path' && chmod 700 '$remote_script_path'" <<'REMOTE_UPDATE_SCRIPT'
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

if [ "$(id -u)" -ne 0 ]; then
  remote_info "checking sudo access"
  sudo -v
  remote_info "sudo access granted"
else
  remote_info "running as root"
fi

remote_info "checking Docker daemon"
run_sudo_timeout 30 docker info >/dev/null
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

remote_info "removing current collector before image cleanup"
run_sudo docker rm -f "$REMOTE_CONTAINER_NAME" 2>/dev/null || true
run_sudo docker rm -f "$REMOTE_OLD_CONTAINER_NAME" 2>/dev/null || true
run_sudo docker rm -f "$LEGACY_CONTAINER_NAME" 2>/dev/null || true
cleanup_panel_images
remote_info "pulling collector image: $COLLECTOR_IMAGE"
run_sudo docker pull "$COLLECTOR_IMAGE"

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
    exit 1
  fi

  VPN_ENDPOINTS="$(IFS=,; echo "${endpoints[*]}")"
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
run_sudo docker run "${docker_args[@]}" "$COLLECTOR_IMAGE" >/dev/null
echo "VPS collector updated"
REMOTE_UPDATE_SCRIPT

  "${SSH_CMD[@]}" -tt "${SSH_ARGS[@]}" "$SSH_TARGET" "$(printf '%q ' "${remote_env[@]}") bash '$remote_script_path'; status=\$?; rm -f '$remote_script_path'; exit \$status"
}

local_pull_args=()
local_run_args=()
if [ -n "${LOCAL_DOCKER_PLATFORM:-}" ]; then
  local_pull_args+=(--platform "$LOCAL_DOCKER_PLATFORM")
  local_run_args+=(--platform "$LOCAL_DOCKER_PLATFORM")
fi

LOCAL_IMAGE_TO_RUN="$REPO_IMAGE"
current_container_image=""
if docker ps -a --format '{{.Names}}' | grep -Fxq "$LOCAL_CONTAINER_NAME"; then
  current_container_image="$(docker inspect -f '{{.Image}}' "$LOCAL_CONTAINER_NAME")"
fi

if [ "$CHECK_UPDATES" = "yes" ]; then
  echo "Checking for Amnezia Panel updates..."
  if run_with_timeout 20 docker pull "${local_pull_args[@]}" "$REPO_IMAGE"; then
    latest_image="$(docker image inspect -f '{{.Id}}' "$REPO_IMAGE")"

    if [ -n "$current_container_image" ] && [ "$current_container_image" != "$latest_image" ]; then
      if ask_yes_no "A newer Amnezia Panel image is available. Update local panel and VPS collector?" "y"; then
        update_remote_collector
        docker rm -f "$LOCAL_CONTAINER_NAME" >/dev/null 2>&1 || true
        LOCAL_IMAGE_TO_RUN="$REPO_IMAGE"
      else
        echo "Keeping the currently installed image."
        LOCAL_IMAGE_TO_RUN="$current_container_image"
      fi
    fi
  else
    echo "WARNING: update check timed out or failed; starting the installed panel."
    if [ -n "$current_container_image" ]; then
      LOCAL_IMAGE_TO_RUN="$current_container_image"
    fi
  fi
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

container_profile=""
if docker ps -a --format '{{.Names}}' | grep -Fxq "$LOCAL_CONTAINER_NAME"; then
  container_profile="$(docker inspect -f '{{ index .Config.Labels "amnezia.panel.profile" }}' "$LOCAL_CONTAINER_NAME" 2>/dev/null || true)"
fi

if [ -n "$container_profile" ] && [ "$container_profile" != "$PROFILE_NAME" ]; then
  docker rm -f "$LOCAL_CONTAINER_NAME" >/dev/null 2>&1 || true
fi

if docker ps --format '{{.Names}}' | grep -Fxq "$LOCAL_CONTAINER_NAME"; then
  :
elif docker ps -a --format '{{.Names}}' | grep -Fxq "$LOCAL_CONTAINER_NAME"; then
  docker start "$LOCAL_CONTAINER_NAME" >/dev/null
else
  docker run -d \
    "${local_run_args[@]}" \
    --name "$LOCAL_CONTAINER_NAME" \
    --restart unless-stopped \
    --label "amnezia.panel.profile=$PROFILE_NAME" \
    --add-host host.docker.internal:host-gateway \
    -p "127.0.0.1:${LOCAL_PANEL_PORT}:9000" \
    -v "$DATA_DIR:/app/data" \
    -e VPN_PANEL_LISTEN=0.0.0.0:9000 \
    -e "VPN_REMOTE_URL=http://host.docker.internal:${LOCAL_TUNNEL_PORT}" \
    -e "VPN_REMOTE_TOKEN=$VPN_PANEL_TOKEN" \
    "$LOCAL_IMAGE_TO_RUN" >/dev/null
fi

echo "Amnezia Panel is running:"
echo "http://127.0.0.1:${LOCAL_PANEL_PORT}"
echo "Profile: $PROFILE_NAME"
CLI_SCRIPT

  chmod 700 "$CLI_PATH"
}
