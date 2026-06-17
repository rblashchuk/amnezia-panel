# Amnezia Panel

Lightweight panel for self-hosted AmneziaVPN / WireGuard live stats and traffic history.

## Install

Run on your local machine:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts/install.sh | bash
```

The installer asks for VPS SSH connection settings, installs the collector on
the VPS, starts an SSH tunnel, and runs the web panel locally at
`http://127.0.0.1:9000`.

The VPS installation step needs root privileges to install/start Docker, create
`/opt/amnezia-panel`, and run the collector container. If the SSH user is not
`root`, the remote host may ask for the user's sudo password. The installer does
not store that password.

During setup you can choose one of the SSH authentication methods:

- SSH config / agent / interactive prompt
- identity file
- password-only SSH login

For SSH config and identity-file modes, the installer inspects `~/.ssh` and
offers known `Host` aliases and private key files as an interactive menu.

For password-only SSH login, install `sshpass` locally if you want to enter the
SSH password once during setup. Without `sshpass`, the system `ssh` command will
ask for the password when it connects.

Optional non-interactive settings:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts/install.sh \
  | VPS_HOST=203.0.113.10 VPS_USER=root VPS_PORT=22 bash
```

Supported Amnezia containers are `amnezia-awg2` and `amnezia-wireguard`.
You can override auto-discovery with `VPN_ENDPOINTS`, for example:
`VPN_ENDPOINTS=awg:amnezia-awg2:awg,wireguard:amnezia-wireguard:wg`.

## Uninstall

Run as root:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts/uninstall.sh | bash
```
