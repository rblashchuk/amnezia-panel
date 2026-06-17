#!/usr/bin/env bash

INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# shellcheck disable=SC1090
. "$INSTALLER_DIR/common.sh"
# shellcheck disable=SC1090
. "$INSTALLER_DIR/profile.sh"
# shellcheck disable=SC1090
. "$INSTALLER_DIR/ssh.sh"
# shellcheck disable=SC1090
. "$INSTALLER_DIR/remote.sh"
# shellcheck disable=SC1090
. "$INSTALLER_DIR/local.sh"

run_install() {
  step 1 "Collecting VPS connection settings..."
  ask PROFILE_NAME "Connection profile name" "default"
  set_profile_paths
  collect_ssh_settings

  if [ -z "$VPN_PANEL_TOKEN" ]; then
    if command -v openssl >/dev/null 2>&1; then
      VPN_PANEL_TOKEN="$(openssl rand -hex 24)"
    else
      VPN_PANEL_TOKEN="$(date +%s)-$RANDOM-$RANDOM-$RANDOM"
    fi
  fi

  configure_ssh_command

  warn "VPS installation requires root privileges for Docker, /opt/amnezia-panel, and container management."
  warn "If SSH user is not root, the remote host may ask for sudo password. It is not stored by this installer."

  step 2 "Checking local environment..."
  command -v docker >/dev/null 2>&1 || die "docker not installed locally"
  docker info >/dev/null 2>&1 || die "local docker daemon not accessible"
  command -v ssh >/dev/null 2>&1 || die "ssh client not installed locally"

  step 3 "Checking SSH connection..."
  "${SSH_CMD[@]}" "${SSH_ARGS[@]}" "$SSH_TARGET" "echo connected >/dev/null"

  step 4 "Checking image updates..."
  detect_image_update

  step 5 "Installing VPS collector..."
  install_remote_collector

  step 6 "Starting SSH tunnel..."
  start_ssh_tunnel

  step 7 "Installing local panel proxy..."
  install_local_panel
  verify_local_panel

  save_profile
  install_cli

  step 8 "Done"
  echo ""
  success "VPS collector installed on $SSH_TARGET"
  success "local panel proxy is running"
  success "command installed: $CLI_PATH"
  echo "Access: http://127.0.0.1:${LOCAL_PANEL_PORT}"
  if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    warn "$BIN_DIR is not in PATH. Add this to your shell profile:"
    echo "export PATH=\"$BIN_DIR:\$PATH\""
  fi
  echo ""
  echo "The SSH tunnel is controlled by: $CONTROL_SOCKET"
}
