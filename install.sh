#!/usr/bin/env bash

set -e

REPO="https://github.com/USERNAME/vpn-panel.git"
APP="vpn-panel"
INSTALL_DIR="/opt/vpn-panel"
SERVICE="/etc/systemd/system/vpn-panel.service"

echo "[1/6] Installing dependencies..."

if ! command -v go >/dev/null 2>&1; then
echo "Go not found. Installing..."
apt update
apt install -y golang-go
fi

if ! command -v git >/dev/null 2>&1; then
apt update
apt install -y git
fi

echo "[2/6] Cloning repo..."

rm -rf "$INSTALL_DIR"
git clone "$REPO" "$INSTALL_DIR"

cd "$INSTALL_DIR"

echo "[3/6] Building..."

go mod tidy
go build -o $APP ./cmd/server

echo "[4/6] Installing binary..."

chmod +x $APP

echo "[5/6] Creating systemd service..."

cat > $SERVICE <<EOF
[Unit]
Description=VPN Panel
After=network.target docker.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$APP
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[6/6] Starting service..."

systemctl daemon-reload
systemctl enable vpn-panel
systemctl restart vpn-panel

echo "DONE."
echo "Panel runs on 127.0.0.1:9000 (use SSH tunnel)"
    