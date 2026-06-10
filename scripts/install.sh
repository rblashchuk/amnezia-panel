#!/usr/bin/env bash
set -euo pipefail

REPO="rblashchuk/vpn-panel"
INSTALL_DIR="/opt/vpn-panel"
BIN="vpn-panel"
SERVICE="/etc/systemd/system/vpn-panel.service"
URL="https://github.com/$REPO/releases/latest/download/vpn-panel-linux-amd64"

echo "[1/7] Checking environment..."

# Docker check
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed"
  exit 1
fi

if ! docker ps >/dev/null 2>&1; then
  echo "ERROR: docker is not accessible (try root or add user to docker group)"
  exit 1
fi

# Systemd check
if ! command -v systemctl >/dev/null 2>&1; then
  echo "ERROR: systemd not available"
  exit 1
fi

# Architecture check
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    echo "Architecture: amd64"
    ;;
  *)
    echo "ERROR: unsupported arch: $ARCH"
    exit 1
    ;;
esac

echo "[2/7] Creating install dir..."

mkdir -p "$INSTALL_DIR"

echo "[3/7] Downloading binary..."

curl -fL "$URL" -o "$INSTALL_DIR/$BIN"

chmod +x "$INSTALL_DIR/$BIN"

echo "[4/7] Installing systemd service..."

cat > "$SERVICE" <<EOF
[Unit]
Description=VPN Panel
After=network.target docker.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BIN
Restart=always
RestartSec=5

Environment=VPN_CONTAINER=amnezia-awg

[Install]
WantedBy=multi-user.target
EOF

echo "[5/7] Reloading systemd..."

systemctl daemon-reload

echo "[6/7] Enabling service..."

systemctl enable vpn-panel >/dev/null 2>&1 || true

echo "[7/7] Starting service..."

systemctl restart vpn-panel

echo ""
echo "OK: vpn-panel installed"
echo "Access: ssh -L 9000:127.0.0.1:9000 user@server"