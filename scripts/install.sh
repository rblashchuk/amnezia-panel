#!/usr/bin/env bash
set -euo pipefail

SCRIPT_BASE_URL="${SCRIPT_BASE_URL:-https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts}"
INSTALLER_FILES=(
  common.sh
  profile.sh
  ssh.sh
  remote.sh
  local.sh
  main.sh
)

download_file() {
  local url="$1"
  local path="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$path"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$path" "$url"
  else
    echo "ERROR: curl or wget is required to download installer modules" >&2
    exit 1
  fi
}

resolve_local_installer_dir() {
  local source_path="${BASH_SOURCE[0]:-}"
  local script_dir

  [ -n "$source_path" ] || return 1
  [ -f "$source_path" ] || return 1

  script_dir="$(cd "$(dirname "$source_path")" && pwd)"
  [ -f "$script_dir/installer/main.sh" ] || return 1

  printf '%s\n' "$script_dir/installer"
}

prepare_installer_dir() {
  if INSTALLER_DIR="$(resolve_local_installer_dir)"; then
    export INSTALLER_DIR
    return
  fi

  INSTALLER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/amnezia-panel-installer.XXXXXX")"
  export INSTALLER_DIR

  local file
  for file in "${INSTALLER_FILES[@]}"; do
    download_file "$SCRIPT_BASE_URL/installer/$file" "$INSTALLER_DIR/$file"
  done
}

prepare_installer_dir

# shellcheck disable=SC1090
. "$INSTALLER_DIR/main.sh"

run_install "$@"
