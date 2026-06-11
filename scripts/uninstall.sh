#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/vpn-panel"

echo "[1/3] Stopping stack..."
cd "$INSTALL_DIR" || true
docker compose down -v 2>/dev/null || true

echo "[2/3] Removing files..."
rm -rf "$INSTALL_DIR"

echo "[3/3] Done"

echo "vpn-panel uninstalled"