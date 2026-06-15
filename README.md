# VPN Panel

Lightweight panel for self-hosted AmneziaVPN / WireGuard live stats and traffic history.

## Install

Run as root:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/vpn-panel/master/scripts/install.sh | bash
```

The installer supports two WireGuard data sources:

```bash
# Auto-discover supported Amnezia Docker containers.
VPN_SOURCE=docker bash scripts/install.sh

# Or pass sources explicitly: protocol:container:command.
VPN_ENDPOINTS=awg:amnezia-awg2:awg,wireguard:amnezia-wireguard:wg bash scripts/install.sh

# Read wg stats from the host network namespace.
VPN_SOURCE=local bash scripts/install.sh
```

Supported Amnezia containers for Docker mode are `amnezia-awg2` and `amnezia-wireguard`.

The panel listens on `127.0.0.1:9000` on the host by default. Use an SSH tunnel or a reverse proxy with authentication for remote access.

## Uninstall

Run as root:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/vpn-panel/master/scripts/uninstall.sh | bash
```
