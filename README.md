# Tailscale Plus for Omarchy

A keyboard-first, native Omarchy control panel for Tailscale. It keeps the
look and interaction model of Omarchy's built-in network panels while exposing
the settings people commonly need from the official Tailscale clients.

> Community plugin: not affiliated with, sponsored by, or endorsed by
> Tailscale, Omarchy, or 37signals.

## Highlights

- Connect, disconnect, authenticate, and switch Tailscale accounts.
- Log in to Tailscale or alternate self-hosted Headscale control servers from
  the panel.
- Select any advertised Tailnet, Headscale, or Mullvad exit node from one
  compact dropdown; choose **None** to disable exit-node routing.
- Show enabled controls with Omarchy's highlighted state and disabled controls
  with the standard dimmed state.
- Toggle Tailscale DNS, advertised subnet routes, exit-node LAN access,
  shields-up mode, Tailscale SSH, web management, exit-node advertising,
  update checks, automatic updates, and posture reporting.
- Browse peers, copy names and IPv4/IPv6 addresses, and send files with
  Taildrop.
- Navigate by mouse or keyboard.
- Optionally store a different systemd-resolved DNS server for each control
  server and switch it together with an exit node.
- Choose exactly one DNS mode: Tailnet-provided DNS, exit-node custom DNS, or
  local network DNS.

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

The Exit Nodes selector always shows the current choice in its collapsed row.
Open it to see **None** followed by every exit node advertised on the active
Tailnet or Headscale network. The selected row is highlighted. Choosing another
row switches gateways directly; choosing **None** disables exit-node routing
and restores the DNS behavior configured for that control server.

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
| Login server URL | Tailscale's public control server | Server offered by the panel's login action |
| Per-tailnet DNS map | `{}` | JSON map from normalized control-server URL to resolver address |

They can be changed through Omarchy's plugin settings or from the CLI:

```bash
omarchy bar set hehh2001.tailscale-plus refreshIntervalSec 30 --json
omarchy bar set hehh2001.tailscale-plus manageExitNodeDns true --json
omarchy bar set hehh2001.tailscale-plus exitNodeDns '<resolver-ip>'
omarchy bar set hehh2001.tailscale-plus loginServer 'https://headscale.example.com'
omarchy bar set hehh2001.tailscale-plus exitNodeDnsMap \
  '{"https://headscale.example.com":"192.0.2.53"}'
```

Do not copy the placeholder literally. Use only a resolver you control or
trust and that remains reachable while the chosen exit node is active.

## Multiple Tailnets and Headscale servers

The always-visible **Tailnet** section near the top of the panel contains the
current control server and a switch field for entering another Headscale/Tailscale
server. It is available even while Tailscale is
disconnected. The custom DNS field sits directly below
**Settings → DNS mode → Exit-node custom DNS**:

1. **Switch to another network** accepts an `http://` or `https://`
   control-server URL, or nothing for official Tailscale. The action logs out
   of the current tailnet first (required by Tailscale before it can bind to a
   different control server), then starts
   `tailscale up --login-server=<url>` (or plain `tailscale up` for
   official Tailscale). If browser authentication is needed, the panel opens
   the URL emitted by the local Tailscale CLI.
2. **DNS server for this tailnet** accepts an IPv4 or IPv6 resolver.
   Saving it stores the resolver under the normalized control-server URL.
   The editor is integrated under **Exit-node custom DNS**: it expands when
   that mode is selected and collapses when another DNS mode is chosen. On a
   first-time setup, clicking the custom mode opens the editor; saving a valid
   resolver activates the mode.

When **Exit Node** is set to **None**, the saved custom resolver is retained but
is not shown as active: the editor collapses and **Local network DNS** is
highlighted. Selecting an exit node again restores the saved custom mode and
expands its editor.

Existing profiles remain available through the Connections section and
`tailscale switch`. Whenever a profile switch changes `ControlURL`, the panel
selects the matching DNS entry automatically. A legacy single `exitNodeDns`
setting remains supported as a fallback for users upgrading from version 1.0.
If a saved profile has expired or the client is logged out, selecting that
connection starts a fresh login against the configured login server instead of
repeatedly attempting an invalid profile switch.

The panel passes arguments directly to the Tailscale process without invoking
a shell. Login URLs must use HTTP or HTTPS, and DNS values must pass address
validation. Authentication keys and identity-provider secrets are never
stored in plugin settings.

## Optional exit-node DNS integration

This feature is for networks whose policy routing depends on a particular DNS
resolver. It is not required for ordinary Tailscale exit nodes. Resolver
selection is keyed by the active Tailscale `ControlURL`, so separate Tailnets
or Headscale deployments can use separate DNS servers.

When configured, selecting an exit node keeps Tailscale's own DNS takeover off
and assigns the configured resolver plus the `~.` route to `tailscale0`.
Removing the exit node reverts `tailscale0`, allowing the current local network
resolver to take over again.

If an exit node is already active when the shell or plugin restarts (for
example after an update or reboot), the plugin re-applies the configured
resolver automatically instead of leaving DNS on the local uplink. If the
privileged helper is not installed or authorized, the panel reports the error
once; install the helper and toggle the exit node, or restart the shell, to
retry.

The three DNS modes are mutually exclusive. **Tailscale DNS** enables
`accept-dns` and reverts the custom resolver. **Exit-node custom DNS** disables
`accept-dns` and applies the per-server resolver only while an exit node is
active. **Local network DNS** disables `accept-dns` and reverts the custom
resolver. The panel never intentionally enables both DNS managers together.

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

The sudo rule permits only the fixed helper path with **no arguments**. The
plugin sends a one-line `on <resolver>` / `off` request over stdin. The helper
accepts only the `tailscale0` interface, validates that the resolver is a
canonical IPv4 or IPv6 address with a strict length cap, and performs fixed
`/usr/bin/resolvectl` operations. It cannot run an arbitrary shell command.

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
