# LTE Status for DankMaterialShell

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) bar
widget for the Intel XMM7360 / Fibocom L850-GL LTE modem. It shows whether the modem is
off, powered on or connected. The popout shows the operator, uptime, IP and
traffic, and has buttons to connect and disconnect.

## Requirements

- [xmm7360-systemd](https://github.com/frankizaw/xmm7360-systemd) installed. The widget
  controls `xmm7360.service` and reads `/var/log/xmm7360.log`.
- `iproute2` (`ip`)

## Install

```sh
git clone https://github.com/frankizaw/dms-lte-status \
  ~/.config/DankMaterialShell/plugins/lteStatus
```

Then enable **LTE Status** in DMS Settings > Plugins and add it to your bar.

## License

MIT
