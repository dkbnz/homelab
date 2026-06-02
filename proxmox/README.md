# Proxmox

The homelab runs [Proxmox VE](https://www.proxmox.com/) on a single mini PC. This
directory captures the current state of the host and its guests so the setup is
documented and repeatable.

## Host

- **Node**: `proxmox` at `192.168.1.10/24` (gateway `192.168.1.1`)
- **Proxmox VE**: 8.4
- **CPU**: Intel Core i7-8650U (8 threads)
- **RAM**: 16 GB
- **Storage**:
  - `sda` 64 GB SanDisk SSD - boot, `local` (dir, on `pve-root`) and `local-lvm` (thin pool)
  - `sdb` 931 GB Samsung T7 (ext4) - data disk, mounted by UUID at host `/mnt/t7`,
    bind-mounted into CT 102 (mp1 media, mp3 minecraft). Converted from exFAT to ext4
    so the *arr apps get real ownership + hardlinks.
  - `sdc` 465 GB USB HDD (ext4) - mounted `/mnt/sdc`; empty spare (was the staging
    disk for the T7 exFAT->ext4 conversion, since wiped)
- The `local-lvm` thin pool was extended to fill the volume group after it hit 100%
  (a runaway Docker pull); keep an eye on `pvesm status` before allocating disks.
- **Network**: single bridge `vmbr0` on `eno0`. Onboard WiFi is disabled.

See `/etc/network/interfaces` on the host for the bridge config.

## Guests

| ID  | Type | Name      | Address          | Purpose                                  |
|-----|------|-----------|------------------|------------------------------------------|
| 100 | VM   | haos12.4  | DHCP             | Home Assistant OS 12.4 (Zigbee + BT USB) |
| 101 | LXC  | adguard   | `192.168.1.20`   | AdGuard Home DNS / ad blocking           |
| 102 | LXC  | docker    | `192.168.1.30`   | Docker host (jellystack media stack + watchtower) |

All three were created with the [community Proxmox helper scripts](https://community-scripts.github.io/ProxmoxVE/).
Guest configs are snapshotted in `guests/` (`*.conf`), application config sits
alongside (`guests/adguard/`, `guests/docker/`).

> Note: AdGuard Home now binds `0.0.0.0` (serves DNS on the LXC's IP `192.168.1.20`)
> and provides DNS rewrites for `jellyfin.home` / `jellyseerr.home`. It previously
> bound `192.168.1.100` — an address the LXC doesn't have — so it crash-looped for
> ~8 days until this was fixed. Point client DNS at `192.168.1.20` to use it.

## Updates & automatic updates

| Component | Mechanism | Auto? |
|-----------|-----------|-------|
| Debian + Proxmox packages (host) | `unattended-upgrades` (Debian + Proxmox no-subscription origins) | yes, daily |
| Debian packages (CT 101, CT 102) | `unattended-upgrades` | yes, daily |
| Kernel/glibc reboot (host) | `config/apt/52unattended-reboot.conf` → reboots 04:30 when needed | yes |
| Docker images (CT 102) | watchtower, daily 04:00 (`guests/docker/watchtower.compose.yml`) | yes |
| Home Assistant (VM 100) | Supervisor self-updates; addon auto-update is per-addon in the HA UI; core/OS are manual (breaking-change risk) | partial |

Apply everything on demand:

```shell
# host + both LXCs
ssh homelab 'export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a; \
  for c in 101 102; do pct exec $c -- apt-get update -qq && pct exec $c -- apt-get -y full-upgrade; done; \
  apt-get update -qq && apt-get -y full-upgrade'
# container images now (instead of waiting for 04:00)
ssh homelab 'pct exec 102 -- docker compose -f /opt/watchtower/watchtower.compose.yml run --rm watchtower --run-once'
```

A host kernel/glibc update sets `/run/reboot-required`; the 04:30 auto-reboot then
activates it (~2 min downtime, all guests have `onboot: 1`). Reboot sooner with
`ssh homelab reboot` during a maintenance window.

## Reconcile live state into the repo

`scripts/snapshot.sh` pulls the live guest configs and the AdGuard config off the
host (over `ssh homelab`) so changes made in the Proxmox UI can be committed:

```shell
proxmox/scripts/snapshot.sh
git add -p && git commit
```

The `*.conf` files carry comments, so the script writes fresh dumps to `/tmp` for
you to diff rather than overwriting them.

## Rebuild from scratch

1. Install Proxmox VE on the host. Configure `vmbr0` on `eno0` (see `/etc/network/interfaces`).
2. Recreate each guest with the matching community helper script, then apply the
   tracked config:
   - VM 100: HAOS VM script, then `qm set 100` for USB passthrough (`usb0` Zigbee, `usb1` Intel BT).
   - CT 101: AdGuard script, then drop `guests/adguard/AdGuardHome.yaml` into `/opt/AdGuardHome/`.
   - CT 102: Docker script, then add storage and tun passthrough per `guests/102-docker.conf`
     (mount the ext4 T7 at `/mnt/t7`, add mp0/mp1/mp2/mp3, the two `lxc.*` tun lines).
     Deploy watchtower (`guests/docker/watchtower.compose.yml`), the jellystack
     (see `guests/docker/jellystack.md`), and the minecraft server
     (see `guests/docker/minecraft.md`).
3. Deploy additional service stacks onto CT 102 as needed (see the repo root `services/`).
