#!/usr/bin/env bash

PANEL_IMAGE="${PANEL_IMAGE:-${REPO_IMAGE:-ghcr.io/rblashchuk/amnezia-panel:latest}}"
COLLECTOR_IMAGE="${COLLECTOR_IMAGE:-ghcr.io/rblashchuk/amnezia-panel-collector:latest}"
REPO_IMAGE="$PANEL_IMAGE"

LOCAL_CONTAINER_NAME="${LOCAL_CONTAINER_NAME:-amnezia-panel}"
REMOTE_CONTAINER_NAME="${REMOTE_CONTAINER_NAME:-amnezia-panel-collector}"
REMOTE_OLD_CONTAINER_NAME="${REMOTE_OLD_CONTAINER_NAME:-amnezia-panel}"
LEGACY_CONTAINER_NAME="${LEGACY_CONTAINER_NAME:-vpn-panel}"

DATA_ROOT="${DATA_ROOT:-$HOME/.amnezia-panel}"
DATA_DIR="$DATA_ROOT/data"
PROFILES_DIR="$DATA_ROOT/profiles"
CURRENT_PROFILE_PATH="$DATA_ROOT/current-profile"
PROFILE_NAME="${PROFILE_NAME:-}"
PROFILE_PATH="$DATA_ROOT/profile.env"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
CLI_PATH="$BIN_DIR/amnezia-panel"
REMOTE_DATA_ROOT="${REMOTE_DATA_ROOT:-/opt/amnezia-panel}"
REMOTE_DATA_DIR="$REMOTE_DATA_ROOT/data"

LOCAL_PANEL_PORT="${LOCAL_PANEL_PORT:-${PANEL_PORT:-9000}}"
LOCAL_TUNNEL_PORT="${LOCAL_TUNNEL_PORT:-19000}"
REMOTE_COLLECTOR_PORT="${REMOTE_COLLECTOR_PORT:-9000}"
LOCAL_DOCKER_PLATFORM="${LOCAL_DOCKER_PLATFORM:-}"

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
TOTAL_STEPS=8
LOCAL_IMAGE_TO_RUN="$REPO_IMAGE"
REMOTE_UPDATE_MODE="install"

if [ -z "$LOCAL_DOCKER_PLATFORM" ]; then
  case "$(uname -m)" in
    arm64|aarch64)
      LOCAL_DOCKER_PLATFORM="linux/amd64"
      ;;
  esac
fi

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
  echo "${BLUE}${BOLD}[$1/$TOTAL_STEPS]${RESET} $2"
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

ask_yes_no() {
  local var_name="$1"
  local prompt="$2"
  local default_value="${3:-n}"
  local answer

  if [ -n "${!var_name:-}" ]; then
    return
  fi

  if [ "$default_value" = "y" ]; then
    read -r -p "$prompt [Y/n]: " answer < "$TTY"
    answer="${answer:-y}"
  else
    read -r -p "$prompt [y/N]: " answer < "$TTY"
    answer="${answer:-n}"
  fi

  case "$answer" in
    y|Y|yes|YES) printf -v "$var_name" '%s' "yes" ;;
    *) printf -v "$var_name" '%s' "no" ;;
  esac
}

sanitize_profile_name() {
  local value="$1"
  value="${value// /-}"
  value="$(printf '%s' "$value" | tr -cd '[:alnum:]_.-')"

  if [ -z "$value" ]; then
    value="default"
  fi

  printf '%s\n' "$value"
}

set_profile_paths() {
  PROFILE_NAME="$(sanitize_profile_name "${PROFILE_NAME:-default}")"
  PROFILE_PATH="$PROFILES_DIR/$PROFILE_NAME.env"
}
