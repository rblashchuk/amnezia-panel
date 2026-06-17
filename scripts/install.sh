#!/usr/bin/env bash
set -euo pipefail

REPO_IMAGE="${REPO_IMAGE:-ghcr.io/rblashchuk/amnezia-panel:latest}"

LOCAL_CONTAINER_NAME="${LOCAL_CONTAINER_NAME:-amnezia-panel}"
REMOTE_CONTAINER_NAME="${REMOTE_CONTAINER_NAME:-amnezia-panel-collector}"
LEGACY_CONTAINER_NAME="${LEGACY_CONTAINER_NAME:-vpn-panel}"

DATA_ROOT="${DATA_ROOT:-$HOME/.amnezia-panel}"
DATA_DIR="$DATA_ROOT/data"
REMOTE_DATA_ROOT="${REMOTE_DATA_ROOT:-/opt/amnezia-panel}"
REMOTE_DATA_DIR="$REMOTE_DATA_ROOT/data"

LOCAL_PANEL_PORT="${LOCAL_PANEL_PORT:-${PANEL_PORT:-9000}}"
LOCAL_TUNNEL_PORT="${LOCAL_TUNNEL_PORT:-19000}"
REMOTE_COLLECTOR_PORT="${REMOTE_COLLECTOR_PORT:-9000}"

VPN_SOURCE="${VPN_SOURCE:-docker}"
VPN_ENDPOINTS="${VPN_ENDPOINTS:-}"
VPN_PANEL_TOKEN="${VPN_PANEL_TOKEN:-}"

VPS_HOST="${VPS_HOST:-}"
VPS_USER="${VPS_USER:-}"
VPS_PORT="${VPS_PORT:-}"
VPS_SSH_KEY="${VPS_SSH_KEY:-}"
VPS_AUTH_METHOD="${VPS_AUTH_METHOD:-}"
VPS_PASSWORD="${VPS_PASSWORD:-}"

TTY="/dev/tty"

if [ -t 1 ]; then
  BOLD="$(tput bold 2>/dev/null || true)"
  DIM="$(tput dim 2>/dev/null || true)"
  RED="$(tput setaf 1 2>/dev/null || true)"
  GREEN="$(tput setaf 2 2>/dev/null || true)"
  YELLOW="$(tput setaf 3 2>/dev/null || true)"
  BLUE="$(tput setaf 4 2>/dev/null || true)"
  RESET="$(tput sgr0 2>/dev/null || true)"
else
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  RESET=""
fi

step() {
  echo "${BLUE}${BOLD}[$1/8]${RESET} $2"
}

info() {
  echo "${DIM}$*${RESET}"
}

success() {
  echo "${GREEN}OK:${RESET} $*"
}

warn() {
  echo "${YELLOW}NOTE:${RESET} $*"
}

die() {
  echo "${RED}ERROR:${RESET} $*" >&2
  exit 1
}

step 1 "Collecting VPS connection settings..."

ask() {
  local var_name="$1"
  local prompt="$2"
  local default_value="${3:-}"
  local current_value="${!var_name:-}"

  if [ -n "$current_value" ]; then
    return
  fi

  if [ -n "$default_value" ]; then
    read -r -p "$prompt [$default_value]: " current_value < "$TTY"
    current_value="${current_value:-$default_value}"
  else
    read -r -p "$prompt: " current_value < "$TTY"
  fi

  printf -v "$var_name" '%s' "$current_value"
}

ask_secret() {
  local var_name="$1"
  local prompt="$2"
  local current_value="${!var_name:-}"

  if [ -n "$current_value" ]; then
    return
  fi

  read -r -s -p "$prompt: " current_value < "$TTY"
  echo ""

  printf -v "$var_name" '%s' "$current_value"
}

select_option() {
  local var_name="$1"
  local prompt="$2"
  shift 2
  local options=("$@")

  if [ -n "${!var_name:-}" ]; then
    return
  fi

  if [ "${#options[@]}" -eq 0 ]; then
    return 1
  fi

  echo ""
  echo "${BOLD}${prompt}:${RESET}"
  local i
  for i in "${!options[@]}"; do
    printf "  %d) %s\n" "$((i + 1))" "${options[$i]}"
  done
  printf "  %d) Manual input\n" "$((${#options[@]} + 1))"

  local choice
  read -r -p "Choose [1]: " choice < "$TTY"
  choice="${choice:-1}"

  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
    printf -v "$var_name" '%s' "${options[$((choice - 1))]}"
    return 0
  fi

  return 1
}

ssh_config_hosts() {
  local config_file="$HOME/.ssh/config"
  [ -f "$config_file" ] || return 0

  awk '
    BEGIN { IGNORECASE = 1 }
    /^[[:space:]]*Host[[:space:]]+/ {
      for (i = 2; i <= NF; i++) {
        if ($i !~ /[*?]/) {
          print $i
        }
      }
    }
  ' "$config_file" | sort -u
}

ssh_identity_files() {
  local ssh_dir="$HOME/.ssh"
  [ -d "$ssh_dir" ] || return 0

  find "$ssh_dir" -maxdepth 1 -type f ! -name "*.pub" ! -name "config" ! -name "known_hosts*" -print 2>/dev/null \
    | while IFS= read -r file; do
        if grep -q "BEGIN .*PRIVATE KEY" "$file" 2>/dev/null; then
          printf '%s\n' "$file"
        fi
      done \
    | sort
}

read_lines_into_array() {
  local array_name="$1"
  shift
  local line

  eval "$array_name=()"
  while IFS= read -r line; do
    eval "$array_name+=(\"\$line\")"
  done < <("$@")
}

if [ -z "$VPS_AUTH_METHOD" ]; then
  echo ""
  echo "${BOLD}SSH authentication method:${RESET}"
  echo "  1) SSH config Host alias"
  echo "  2) Identity file"
  echo "  3) Password only"
  echo "  4) SSH agent / default SSH behavior"
  read -r -p "Choose [4]: " VPS_AUTH_METHOD < "$TTY"
  VPS_AUTH_METHOD="${VPS_AUTH_METHOD:-4}"
fi

case "$VPS_AUTH_METHOD" in
  1|ssh-config|config)
    VPS_AUTH_METHOD="ssh-config"
    read_lines_into_array ssh_hosts ssh_config_hosts
    select_option VPS_HOST "SSH config Host alias" "${ssh_hosts[@]}" || true
    ask VPS_HOST "SSH config Host alias"
    ;;
  2|identity|identity-file|key)
    VPS_AUTH_METHOD="identity-file"
    ask VPS_HOST "VPS host or IP"
    ask VPS_USER "SSH user" "root"
    ask VPS_PORT "SSH port" "22"
    read_lines_into_array identity_files ssh_identity_files
    select_option VPS_SSH_KEY "SSH private key" "${identity_files[@]}" || true
    ask VPS_SSH_KEY "SSH private key path"
    ;;
  3|password|password-only)
    VPS_AUTH_METHOD="password-only"
    ask VPS_HOST "VPS host or IP"
    ask VPS_USER "SSH user" "root"
    ask VPS_PORT "SSH port" "22"
    if command -v sshpass >/dev/null 2>&1; then
      ask_secret VPS_PASSWORD "SSH password"
    else
      warn "sshpass is not installed locally; ssh will ask for the password during connection."
      warn "The installer will not store the SSH password."
    fi
    ;;
  4|default|agent|ssh-agent)
    VPS_AUTH_METHOD="default"
    ask VPS_HOST "VPS host or IP"
    ask VPS_USER "SSH user" "root"
    ask VPS_PORT "SSH port" "22"
    ;;
  *)
    die "unsupported VPS_AUTH_METHOD=$VPS_AUTH_METHOD"
    ;;
esac

if [ -z "$VPS_HOST" ]; then
  die "VPS host is required"
fi

if [ -z "$VPN_PANEL_TOKEN" ]; then
  if command -v openssl >/dev/null 2>&1; then
    VPN_PANEL_TOKEN="$(openssl rand -hex 24)"
  else
    VPN_PANEL_TOKEN="$(date +%s)-$RANDOM-$RANDOM-$RANDOM"
  fi
fi

if [ "$VPS_AUTH_METHOD" = "ssh-config" ]; then
  SSH_TARGET="$VPS_HOST"
else
  SSH_TARGET="${VPS_USER}@${VPS_HOST}"
fi

SSH_CMD=(ssh)
if [ "$VPS_AUTH_METHOD" = "password-only" ] && [ -n "$VPS_PASSWORD" ] && command -v sshpass >/dev/null 2>&1; then
  SSH_CMD=(sshpass -p "$VPS_PASSWORD" ssh)
fi

SSH_ARGS=(-o ServerAliveInterval=30 -o ServerAliveCountMax=3)
if [ "$VPS_AUTH_METHOD" != "ssh-config" ]; then
  SSH_ARGS=(-p "$VPS_PORT" "${SSH_ARGS[@]}")
fi
if [ "$VPS_AUTH_METHOD" = "identity-file" ]; then
  SSH_ARGS+=(-i "$VPS_SSH_KEY")
elif [ "$VPS_AUTH_METHOD" = "password-only" ]; then
  SSH_ARGS+=(-o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no)
fi

warn "VPS installation requires root privileges for Docker, /opt/amnezia-panel, and container management."
warn "If SSH user is not root, the remote host may ask for sudo password. It is not stored by this installer."

step 2 "Checking local environment..."

if ! command -v docker >/dev/null 2>&1; then
  die "docker not installed locally"
fi

if ! docker info >/dev/null 2>&1; then
  die "local docker daemon not accessible"
fi

if ! command -v ssh >/dev/null 2>&1; then
  die "ssh client not installed locally"
fi

step 3 "Checking SSH connection..."

"${SSH_CMD[@]}" "${SSH_ARGS[@]}" "$SSH_TARGET" "echo connected >/dev/null"

step 4 "Installing VPS collector..."

remote_env=(
  "REPO_IMAGE=$REPO_IMAGE"
  "REMOTE_CONTAINER_NAME=$REMOTE_CONTAINER_NAME"
  "LEGACY_CONTAINER_NAME=$LEGACY_CONTAINER_NAME"
  "REMOTE_DATA_ROOT=$REMOTE_DATA_ROOT"
  "REMOTE_DATA_DIR=$REMOTE_DATA_DIR"
  "REMOTE_COLLECTOR_PORT=$REMOTE_COLLECTOR_PORT"
  "VPN_SOURCE=$VPN_SOURCE"
  "VPN_ENDPOINTS=$VPN_ENDPOINTS"
  "VPN_PANEL_TOKEN=$VPN_PANEL_TOKEN"
)

REMOTE_SCRIPT_PATH="/tmp/amnezia-panel-install-$$.sh"

"${SSH_CMD[@]}" "${SSH_ARGS[@]}" "$SSH_TARGET" "cat > '$REMOTE_SCRIPT_PATH' && chmod 700 '$REMOTE_SCRIPT_PATH'" <<'REMOTE_SCRIPT'
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

run_sudo docker pull "$REPO_IMAGE"

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
run_sudo docker rm -f "$LEGACY_CONTAINER_NAME" 2>/dev/null || true

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

run_sudo docker run "${docker_args[@]}" "$REPO_IMAGE"

sleep 1

if ! run_sudo docker ps --format '{{.Names}}' | grep -Fxq "$REMOTE_CONTAINER_NAME"; then
  echo "ERROR: collector container failed to start on VPS"
  run_sudo docker logs "$REMOTE_CONTAINER_NAME" || true
  exit 1
fi

echo "VPS collector installed"
echo "Sources: $VPN_ENDPOINTS"
REMOTE_SCRIPT

"${SSH_CMD[@]}" -tt "${SSH_ARGS[@]}" "$SSH_TARGET" "$(printf '%q ' "${remote_env[@]}") bash '$REMOTE_SCRIPT_PATH'; status=\$?; rm -f '$REMOTE_SCRIPT_PATH'; exit \$status"

step 5 "Starting SSH tunnel..."

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

step 6 "Installing local panel proxy..."

mkdir -p "$DATA_DIR"
chmod 755 "$DATA_DIR"

docker pull "$REPO_IMAGE"

docker rm -f "$LOCAL_CONTAINER_NAME" 2>/dev/null || true

docker run -d \
  --name "$LOCAL_CONTAINER_NAME" \
  --restart unless-stopped \
  --add-host host.docker.internal:host-gateway \
  -p "127.0.0.1:${LOCAL_PANEL_PORT}:9000" \
  -v "$DATA_DIR:/app/data" \
  -e VPN_PANEL_LISTEN=0.0.0.0:9000 \
  -e "VPN_REMOTE_URL=http://host.docker.internal:${LOCAL_TUNNEL_PORT}" \
  -e "VPN_REMOTE_TOKEN=$VPN_PANEL_TOKEN" \
  "$REPO_IMAGE"

step 7 "Verifying local panel..."

sleep 1

if ! docker ps --format '{{.Names}}' | grep -Fxq "$LOCAL_CONTAINER_NAME"; then
  echo "ERROR: local panel container failed to start"
  docker logs "$LOCAL_CONTAINER_NAME" || true
  exit 1
fi

step 8 "Done"
echo ""
success "VPS collector installed on $SSH_TARGET"
success "local panel proxy is running"
echo "Access: http://127.0.0.1:${LOCAL_PANEL_PORT}"
echo ""
echo "The SSH tunnel is controlled by: $CONTROL_SOCKET"
