# extrude: OctoPrint for the Ender 3 V2 Neo

An Orange Pi Lite running OctoPrint, connected over USB to the Creality Ender 3 V2
Neo. It is a standalone LAN host, not a Proxmox guest.

| | |
|---|---|
| Dashboard | http://extrude.home (direct: http://192.168.1.50:5000) |
| SSH | `ssh root@192.168.1.50` or `ssh octoprint@192.168.1.50` (Mac's `id_ed25519` key) |
| Credentials | `extrude.env` (ENCRYPTED via transcrypt) |
| Hardware | Orange Pi Lite: Allwinner H3, 512 MB RAM (484 MB usable), RTL8189FTV Wi-Fi (2.4 GHz only), no Ethernet |
| Storage | 64 GB microSD |
| OS | Armbian 26.11.0-trunk.137 community build, Debian 13 trixie minimal, kernel 6.18.64-current-sunxi |
| Set up | 2026-11-22 |

## Network

- Wi-Fi `iot` on `wlan0`, static `192.168.1.50/24`, gateway `192.168.1.1`, DNS
  AdGuard `192.168.1.20` then `192.168.1.1`. Config: `30-wifis-static.yaml`
  (`/etc/netplan/`, ENCRYPTED via transcrypt).
- Pinned to the Starlink router's 2.4 GHz BSSID `8e:32:ca:29:27:5f`. Both the
  Starlink and the TP-Link repeater (`b0:be:76:77:f8:39`) broadcast `iot`. Pinning
  keeps the Pi off the repeater, which has the ARP problem described in
  `proxmox/host/README.md`. If the Starlink is down, the Pi stays offline; it does not
  fall back to the repeater.
- WPA2-PSK only (`auth: key-management: psk`). The Starlink runs WPA2/WPA3 mixed
  mode with PMF. With netplan's default `WPA-PSK WPA-PSK-SHA256 SAE`, wpa_supplicant
  turns PMF on and the 8189fs driver fails to install the key
  (`Failed to configure IGTK to the driver`), so every association drops.
- To unpin: `cp /root/30-wifis-static.yaml.bak /etc/netplan/30-wifis-static.yaml &&
  netplan apply`. That backup has no BSSID. It still has the SAE key-management
  line, so it will only join the repeater.
- `extrude.home`: AdGuard's `*.home` rewrite sends it to `192.168.1.30`, where Caddy
  (`proxmox/guests/docker/caddy/Caddyfile`) proxies it to `192.168.1.50:5000`. No
  separate DNS entry is needed.

## OctoPrint

- OctoPrint 2.0.1 (installed 2026-11-22) on Python 3.13.5.
- Runs as user `octoprint` from the venv `/home/octoprint/oprint`, via
  `octoprint.service` (`octoprint serve --host 0.0.0.0 --port 5000`).
- Config `/home/octoprint/.octoprint/config.yaml`. Initial settings: serial port
  `AUTO`, 115200 baud, autoconnect; restart, reboot and shutdown commands through
  `sudo` (`/etc/sudoers.d/octoprint` allows only those three).
- The web admin account is created in OctoPrint's first-run wizard. Record it in
  `extrude.env`.
- Update OctoPrint from its own Software Update page, or
  `sudo -u octoprint /home/octoprint/oprint/bin/pip install -U OctoPrint`.
- Logs: `journalctl -u octoprint`, `/home/octoprint/.octoprint/logs/`. The install
  log is `/root/octoprint-provision.log`.

## Files here

| File | On the Pi | Notes |
|---|---|---|
| `extrude.env` | - | Wi-Fi key, BSSID, root and `octoprint` Linux passwords (encrypted) |
| `armbian-preset.env` | `/root/.not_logged_in_yet` | Armbian first-boot preset (encrypted). Deleted by Armbian after first login |
| `30-wifis-static.yaml` | `/etc/netplan/30-wifis-static.yaml` | Netplan Wi-Fi config (encrypted) |
| `install.sh` | `/root/provision/install.sh` | One-time install: hostname, SSH key, packages, OctoPrint venv, sudoers, config, service |
| `octoprint-provision.service` | `/etc/systemd/system/` | Runs `install.sh` once at boot, retries every 2 min on failure, disables itself when done |

## Rebuild

1. Download the image and check it against its `.sha`:
   `https://dl.armbian.com/orangepilite/Trixie_current_minimal` (and `.sha`).
2. `xz -dk` it, then attach it without mounting:
   `hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount <img>`.
3. Write the files into the ext4 partition with e2fsprogs `debugfs -w` (Homebrew
   `e2fsprogs`; macOS cannot mount ext4). Set uid/gid 0 and the modes with `sif`:
   - `armbian-preset.env` to `/root/.not_logged_in_yet` (0600, replacing the empty one)
   - `30-wifis-static.yaml` to `/etc/netplan/` (0600)
   - `install.sh` to `/root/provision/install.sh` (0700), and the SSH public key
     to `/root/provision/authorized_keys` (0600)
   - `octoprint-provision.service` to `/etc/systemd/system/` (0644), plus a symlink
     in `/etc/systemd/system/multi-user.target.wants/`
4. `e2fsck -fn` the partition, detach, then
   `sudo dd if=<img> of=/dev/rdiskN bs=4m status=progress`.
5. Boot. Armbian expands the filesystem, auto-logs in as root on the console and
   applies the preset. The install takes about 30-40 minutes, mostly compiling
   wheels (no armv7 wheels for Python 3.13 for several packages, including Pillow).

## Gotchas found during setup

- Armbian's first-boot network preset picks the first interface `iw dev` lists.
  8189fs creates `wlan0` plus a virtual `wlan1`, and `iw dev` lists `wlan1` first,
  so the preset wrote a config for the wrong interface. That is why the preset here
  has `PRESET_NET_CHANGE_DEFAULTS="0"` and the netplan file is written by hand.
- Armbian sources `/root/provisioning.sh` into its login script on every root
  login, not once. Use the systemd unit instead.
- First login runs `systemctl is-system-running --wait` before creating the user.
  A `Type=oneshot` unit in `multi-user.target` that waits for that user deadlocks
  boot. The unit is `Type=exec` for this reason.
- `/tmp` is a 243 MB tmpfs. pip builds in `/home/octoprint/.cache/pip-build` instead.
- `/var/log` is in zram (Armbian ramlog) and is lost on power loss. Shut down with
  `sudo shutdown -h now`, or from OctoPrint, before pulling power; an unclean power-off
  left the ext4 journal needing replay.
