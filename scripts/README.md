# Scripts

This directory contains the public installer entrypoint and its internal
installer modules.

## Entrypoint

`install.sh` is the only public installer script. It can be run from a local
checkout or through the GitHub one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/rblashchuk/amnezia-panel/master/scripts/install.sh | bash
```

When `install.sh` runs from a local checkout, it uses the adjacent `installer`
directory. When it runs through a pipe, it downloads the required modules from
`scripts/installer` into a temporary directory and then hands control to
`installer/main.sh`.

## Installer Modules

- `installer/common.sh` - shared variables, colors, logging, and simple
  interactive prompts.
- `installer/ssh.sh` - SSH settings collection, `~/.ssh/config` Host alias
  selection, identity file selection, and final SSH command construction.
- `installer/local.sh` - Docker image update check, local SSH tunnel, and local
  web proxy container startup.
- `installer/remote.sh` - Docker installation on the VPS when needed and VPS
  collector startup with the lightweight collector image.
- `installer/profile.sh` - local profile persistence and `amnezia-panel`
  command / `ap` alias installation.
- `installer/main.sh` - top-level installer flow that connects all steps.

## Connection Profiles

The installer stores connection settings as named local profiles under
`~/.amnezia-panel/profiles`. The currently selected profile name is stored in
`~/.amnezia-panel/current-profile`.

When the installer is run again, it uses the current profile as the default
profile name. If that profile exists, its saved SSH and panel settings are
loaded before the interactive SSH questions, so the user only has to answer
fields that are still missing.

For compatibility with earlier installations, the installer also writes
`~/.amnezia-panel/profile.env`, and the `amnezia-panel` command can still use it
as the default profile fallback.

The installed command supports:

```bash
amnezia-panel profiles
amnezia-panel current
amnezia-panel use default
amnezia-panel --profile default
amnezia-panel --no-update-check
amnezia-panel update
ap update
```

## Image Updates

If the local `amnezia-panel` container already exists, the installer pulls the
latest Docker image as an update candidate and compares it with the image id
used by the installed container. When a newer image is available, the user gets
an interactive prompt. If the user accepts, both the local panel and the VPS
collector are updated. If the user declines, the installer keeps the current
local image and does not update the VPS collector image.

The installed `amnezia-panel` command performs the same update check before it
starts the saved SSH tunnel and local web panel. Use `amnezia-panel
--no-update-check` to skip this check for a single run. The update check is
best-effort: if pulling image metadata fails or times out, the command continues
with the currently installed local image.

The local web panel can also check for updates from the Debug tab when the local
Docker socket is mounted into the panel container. The UI performs this check on
open and then roughly once per hour, and shows `ap update` when an update is
available.

The local panel image is `ghcr.io/rblashchuk/amnezia-panel`. The VPS collector
image is `ghcr.io/rblashchuk/amnezia-panel-collector`. Before pulling the
collector image, the installer removes old panel/collector containers and prunes
unused legacy images to avoid filling small VPS disks.
