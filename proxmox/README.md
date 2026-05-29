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
  - `sdb` 931 GB Samsung T7 (exfat) - media disk, mounted at host `/mnt/t7`, bind-mounted into CT 102
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

> Note: AdGuard Home binds to `192.168.1.100` in its own config while the LXC's
> primary interface is `192.168.1.20`. Confirm the intended listen address when
> rebuilding.

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
     (mount the T7 at `/mnt/t7`, add mp0/mp1/mp2, the two `lxc.*` tun lines). Deploy
     watchtower (`guests/docker/watchtower.compose.yml`) and the jellystack
     (see `guests/docker/jellystack.md`).
3. Deploy additional service stacks onto CT 102 as needed (see the repo root `services/`).
