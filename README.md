# Tailscale Plus for Omarchy

A native Omarchy bar plugin that expands the built-in Tailscale panel into a
full settings client while keeping Omarchy's keyboard-first interaction and
visual language.

## Features

- Connect, disconnect, log in, and switch Tailscale accounts.
- Select tailnet or Mullvad exit nodes.
- Highlight active accounts, exit nodes, and settings; inactive items remain dim.
- Toggle subnet routes, LAN access through an exit node, shields-up mode,
  Tailscale SSH, web management, exit-node advertising, update checks,
  automatic updates, and device posture reporting.
- Browse peers, copy names and addresses, and send files with Taildrop.
- Optionally switch system DNS when an exit node is enabled.
- Mouse and keyboard navigation matching the built-in Omarchy panels.

## Install

```bash
omarchy plugin add https://github.com/hehh2001/omarchy-tailscale-plus.git --enable
```

## Optional exit-node DNS switching

Set `Switch DNS with exit node` and `Exit node DNS server` in the plugin
settings. Changing systemd-resolved requires root, while Omarchy's plugin
installer intentionally runs no sudo hooks. Review and install the helper:

```bash
./scripts/install-dns-helper
```

Remove it with `./scripts/uninstall-dns-helper`. Without the helper, ordinary
Tailscale controls still work and the panel shows an actionable DNS error.

## Development

```bash
node tests/model.test.js
omarchy plugin validate .
qmllint Panel.qml Service.qml
```

See the [official Omarchy plugin manual](https://omarchy.org/manual/shell-plugins/).

## Security

Omarchy plugins run unsandboxed as the desktop user. The optional DNS helper
accepts only `on` or `off`, validates the interface name, and performs fixed
`resolvectl` actions. Its sudo rule is scoped to that root-owned helper.

## License

MIT
