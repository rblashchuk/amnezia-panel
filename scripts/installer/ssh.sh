#!/usr/bin/env bash

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

collect_ssh_settings() {
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

  [ -n "$VPS_HOST" ] || die "VPS host is required"
}

configure_ssh_command() {
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
}
