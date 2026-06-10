#!/usr/bin/env bash
set -euo pipefail

SERVICE="vpn-panel.service"
BIN_DIR="/opt/vpn-panel"

echo "[1/5] Stopping service..."

systemctl stop vpn-panel 2>/dev/null || true

echo "[2/5] Disabling service..."

systemctl disable vpn-panel 2>/dev/null || true

echo "[3/5] Removing systemd unit..."

rm -f /etc/systemd/system/$SERVICE

echo "[4/5] Reloading systemd..."

systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

echo "[5/5] Removing files..."

rm -rf "$BIN_DIR"

echo ""
echo "vpn-panel uninstalled"