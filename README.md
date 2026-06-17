# Amnezia Panel

Lightweight panel for self-hosted AmneziaVPN / WireGuard live stats and traffic history.

## Install

Run as root:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts/install.sh | bash
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

## Local proxy mode

Run the collector on the VPS with the regular installer. Optionally protect the
collector API with a token:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts/install.sh \
  | VPN_PANEL_TOKEN=change-me bash
```

Create an SSH tunnel from your local machine to the VPS collector:

```bash
ssh -N -L 19000:127.0.0.1:9000 user@your-vps
```

Then install/run the local proxy with the same installer:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts/install.sh \
  | VPN_PANEL_MODE=local-proxy \
    VPN_REMOTE_URL=http://host.docker.internal:19000 \
    VPN_REMOTE_TOKEN=change-me \
    bash
```

In this mode the local process serves the web UI on localhost and forwards
read-only API calls to the VPS collector.

## Uninstall

Run as root:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts/uninstall.sh | bash
```
