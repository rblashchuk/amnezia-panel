# Amnezia Panel

Amnezia Panel is a local admin panel for self-hosted AmneziaVPN servers.

It is designed to make day-to-day administration more convenient than working
only through the AmneziaVPN client.

The key extra feature is built-in traffic monitoring. A lightweight collector
runs on the VPS, stores traffic history, and the local panel shows live counters
and historical charts for each client.

The local web panel and the VPS collector are shipped as separate Docker images.
The collector image is intentionally minimal because VPS disks are often small.

## Prerequisites

### Local Machine

Supported local environments:

- macOS with Docker Desktop or Colima
- Linux with Docker Engine
- Windows through WSL2 with Docker Desktop WSL integration

Native Windows shells such as PowerShell and `cmd.exe` are not supported yet.
Run the installer from a WSL2 Linux shell instead.

Required local tools:

- `bash`
- `curl` or `wget`
- `ssh`
- Docker CLI connected to a running Docker daemon
- optional: `sshpass` for password-only SSH setup without repeated prompts

The installer runs the web UI locally in Docker and keeps it available only on
`127.0.0.1`. It also creates an SSH tunnel from the local machine to the VPS
collector.

### VPS

Required VPS access:

- Linux server with SSH access
- `root` login or a user with `sudo`
- enough disk space for Docker images and the collector database
- an existing self-hosted AmneziaVPN installation

Docker is required on the VPS. If Docker is missing, the installer will try to
install it automatically on systems with `apt-get`, `dnf`, or `yum`.

## Install

Run on your local machine:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts/install.sh | bash
```

The installer asks for VPS SSH connection settings, installs the collector on
the VPS, starts an SSH tunnel, and runs the web panel locally at
`http://127.0.0.1:9000`.

During setup, you can choose the local web UI port. The default is `9000`.

After installation, the `amnezia-panel` command and the shorter `ap` alias are
installed to `~/.local/bin`. Running either command later starts the saved SSH
tunnel and local web panel again.

Connection settings are saved as named local profiles. The default profile is
used automatically, and additional commands are available:

```bash
amnezia-panel profiles
amnezia-panel current
amnezia-panel use default
amnezia-panel --profile default
amnezia-panel --port 9010
amnezia-panel --no-update-check
ap update
```

On startup, `amnezia-panel` checks whether a newer Docker image is available and
asks before updating the local panel and VPS collector.

When started from an interactive terminal, `amnezia-panel` / `ap` asks which
local web UI port to use. You can also pass it explicitly with `--port`; the
selected value is saved back to the active profile.

The Debug tab can also check for updates. When a newer image is available, it
shows the latest image information and the terminal command to run.

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
