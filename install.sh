#!/usr/bin/env bash

set -e

VERSION="latest"
REPO="rblashchuk/vpn-panel"
INSTALL_DIR="/opt/vpn-panel"
BIN="vpn-panel"

echo "[1/5] Detecting architecture..."

ARCH=$(uname -m)

if [ "$ARCH" = "x86_64" ]; then
  ASSET="vpn-panel-linux-amd64"
else
  echo "Unsupported arch"
  exit 1
fi

echo "[2/5] Downloading binary..."

mkdir -p $INSTALL_DIR

curl -L \
  "https://github.com/$REPO/releases/$VERSION/download/$ASSET" \
  -o $INSTALL_DIR/$BIN

chmod +x $INSTALL_DIR/$BIN

echo "[3/5] Installing systemd service..."

cat > /etc/systemd/system/vpn-panel.service <<EOF
[Unit]
Description=VPN Panel
After=network.target docker.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BIN
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[4/5] Starting service..."

systemctl daemon-reload
systemctl enable vpn-panel
systemctl restart vpn-panel

echo "[5/5] Done. Access via SSH tunnel on 127.0.0.1:9000"