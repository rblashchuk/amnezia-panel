# Amnezia Panel

Amnezia Panel is a local admin panel for self-hosted AmneziaVPN servers.

It is designed to make day-to-day administration more convenient than working
only through the AmneziaVPN client.

The key extra feature is built-in traffic monitoring. A lightweight collector
runs on the VPS, stores traffic history, and the local panel shows live counters
and historical charts for each client.

## Install

Run on your local machine:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts/install.sh | bash
```

The installer asks for VPS SSH connection settings, installs the collector on
the VPS, starts an SSH tunnel, and runs the web panel locally at
`http://127.0.0.1:9000`.

After installation, the `amnezia-panel` command is installed to
`~/.local/bin`. Running it later starts the saved SSH tunnel and local web panel
again.

Connection settings are saved as named local profiles. The default profile is
used automatically, and additional commands are available:

```bash
amnezia-panel profiles
amnezia-panel current
amnezia-panel use default
amnezia-panel --profile default
amnezia-panel --no-update-check
```

On startup, `amnezia-panel` checks whether a newer Docker image is available and
asks before updating the local panel and VPS collector.

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

## Uninstall

Run as root:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts/uninstall.sh | bash
```

## TODO

- Add full client create, revoke, rename, and export flows.
- Expand monitoring support across more AmneziaVPN protocols.
- Improve saved profile management in the web UI.
