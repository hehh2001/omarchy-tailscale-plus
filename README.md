# Tailscale Plus for Omarchy

A keyboard-first, native Omarchy control panel for Tailscale. It keeps the
look and interaction model of Omarchy's built-in network panels while exposing
the settings people commonly need from the official Tailscale clients.

> Community plugin: not affiliated with, sponsored by, or endorsed by
> Tailscale, Omarchy, or 37signals.

## Highlights

- Connect, disconnect, authenticate, and switch Tailscale accounts.
- Select tailnet and Mullvad exit nodes.
- Show enabled controls with Omarchy's highlighted state and disabled controls
  with the standard dimmed state.
- Toggle Tailscale DNS, advertised subnet routes, exit-node LAN access,
  shields-up mode, Tailscale SSH, web management, exit-node advertising,
  update checks, automatic updates, and posture reporting.
- Browse peers, copy names and IPv4/IPv6 addresses, and send files with
  Taildrop.
- Navigate by mouse or keyboard.
- Optionally switch a systemd-resolved DNS server together with an exit node.

## Requirements

- Omarchy with the Quattro shell plugin system.
- Tailscale CLI and `tailscaled` installed and running.
- `wl-copy` for clipboard actions.
- Taildrop enabled by the tailnet administrator to send files.
- Mullvad exit-node access on the tailnet to display Mullvad regions.
- Optional DNS integration: Linux using systemd-resolved, plus `sudo` and
  `visudo` for the separately reviewed helper installation.

The plugin does not bundle Tailscale, modify the coordination server, or
change router configuration.

## Install

```bash
omarchy plugin add https://github.com/hehh2001/omarchy-tailscale-plus.git --enable
```

If the built-in Tailscale widget is already present, disable only its widget to
avoid two icons. This does not stop `tailscaled`:

```bash
omarchy plugin disable omarchy.tailscale
```

The published plugin ID is `hehh2001.tailscale-plus`.

## Use

Left-click the bar icon to open the panel. Right-click toggles the Tailscale
connection. Enabled accounts, exit nodes, and switches are highlighted;
disabled states are dim.

Keyboard shortcuts inside the panel:

| Key | Action |
| --- | --- |
| `j`, `k`, arrows | Move through accounts, exit nodes, settings, and peers |
| `Enter`, `Space` | Activate the selected row or switch |
| `c` | Copy the selected peer's IPv4 address |
| `n` | Copy the selected peer's name |
| `d` | Copy the selected peer's DNS name |
| `s` | Send files to the selected peer with Taildrop |
| `t` | Connect or disconnect Tailscale |
| `r` | Refresh status |
| `Esc` | Close the panel |

## Configuration

The plugin exposes these standard Omarchy widget settings:

| Setting | Default | Purpose |
| --- | --- | --- |
| Refresh interval | `30` seconds | Poll Tailscale status and preferences |
| Switch DNS with exit node | Off | Run the optional DNS helper after exit-node changes |
| Exit node DNS server | Empty | IPv4 or IPv6 resolver reachable through the exit node |
| Privileged DNS helper | `/usr/local/libexec/omarchy-tailscale-plus-dns` | Root-owned helper path |

They can be changed through Omarchy's plugin settings or from the CLI:

```bash
omarchy bar set hehh2001.tailscale-plus refreshIntervalSec 30 --json
omarchy bar set hehh2001.tailscale-plus manageExitNodeDns true --json
omarchy bar set hehh2001.tailscale-plus exitNodeDns '<resolver-ip>'
```

Do not copy the placeholder literally. Use only a resolver you control or
trust and that remains reachable while the chosen exit node is active.

## Optional exit-node DNS integration

This feature is for networks whose policy routing depends on a particular DNS
resolver. It is not required for ordinary Tailscale exit nodes.

When configured, selecting an exit node keeps Tailscale's own DNS takeover off
and assigns the configured resolver plus the `~.` route to `tailscale0`.
Removing the exit node reverts `tailscale0`, allowing the current local network
resolver to take over again.

System DNS changes require privilege. Omarchy intentionally does not execute
plugin install hooks or `sudo`, so the helper is never installed automatically.
Review these files first:

- `scripts/omarchy-tailscale-plus-dns`
- `scripts/install-dns-helper`
- `scripts/uninstall-dns-helper`

Then install it explicitly:

```bash
cd ~/.config/omarchy/plugins/hehh2001.tailscale-plus
./scripts/install-dns-helper
```

The installer creates:

- `/usr/local/libexec/omarchy-tailscale-plus-dns`, owned by root and mode `0755`.
- `/etc/sudoers.d/omarchy-tailscale-plus-dns`, owned by root and mode `0440`.

The sudo rule permits only that fixed helper's `on` and `off` actions. The
helper accepts only the `tailscale0` interface, validates that the resolver is
an IPv4 or IPv6 address, and performs fixed `resolvectl` operations. It cannot
run an arbitrary shell command.

Without the helper, all ordinary Tailscale controls continue working. If DNS
switching is enabled without authorization, the panel reports an actionable
error instead of silently changing system configuration.

## Update

```bash
omarchy plugin update hehh2001.tailscale-plus
```

Review the displayed diff before accepting an update. Marketplace verification
is bound to a specific commit; a newer repository HEAD may not yet have been
reviewed by the marketplace.

## Remove

If the optional helper was installed, remove it first. The script also attempts
to revert the runtime `tailscale0` DNS configuration:

```bash
cd ~/.config/omarchy/plugins/hehh2001.tailscale-plus
./scripts/uninstall-dns-helper
```

Then remove the plugin and optionally restore the built-in widget:

```bash
omarchy plugin remove hehh2001.tailscale-plus
omarchy plugin enable omarchy.tailscale
```

Removing the plugin does not uninstall Tailscale, log out of the tailnet, or
change the coordination server or router.

## Troubleshooting

### The plugin is installed but not visible

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable hehh2001.tailscale-plus
omarchy bar move hehh2001.tailscale-plus --section right
```

### Settings report an operator permission error

Use the panel's operator authorization action, or authorize the current Unix
user with Tailscale's supported operator setting. Review the command before
running it:

```bash
sudo tailscale set --operator="$USER"
```

### Exit-node traffic works but DNS switching fails

Confirm all of the following:

```bash
tailscale debug prefs
resolvectl status tailscale0
sudo -n -l
```

The configured resolver must be reachable through the active exit node. The
optional helper supports systemd-resolved only.

### Two Tailscale icons appear

Disable the built-in bar widget:

```bash
omarchy plugin disable omarchy.tailscale
```

### Inspect shell errors

```bash
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

## Development and verification

The repository follows Omarchy's third-party plugin layout: `manifest.json`
is at the root and points directly to `Panel.qml`.

```bash
node tests/model.test.js
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" Panel.qml Service.qml
```

The model tests cover Tailscale preference parsing. Release testing also checks
plugin discovery, panel open/close, exit-node on/off behavior, DNS reversion,
and peer connectivity.

See the [official Omarchy shell plugin manual](https://omarchy.org/manual/shell-plugins/)
and the [community marketplace publishing guide](https://omarchyplugins.com/publish.html).

## Security and privacy

- Plugins run unsandboxed as the desktop user; review the source before enabling.
- The panel invokes the local Tailscale CLI and does not transmit telemetry of
  its own.
- No credentials, authentication URLs, Tailnet names, host names, private
  addresses, or user-specific DNS servers are included in this repository.
- Tailscale account state remains managed by `tailscaled`.
- The optional helper and sudoers modification require explicit installation
  and should be reviewed as privileged code.
- Report suspected vulnerabilities privately through GitHub security reporting
  rather than opening an issue containing credentials or private network data.

## Credits

Originally derived from Omarchy's MIT-licensed built-in Tailscale panel. The
interface continues to use Omarchy's native Quickshell components and styling.
Tailscale is a trademark of Tailscale Inc.

## License

MIT. See [LICENSE](LICENSE).
