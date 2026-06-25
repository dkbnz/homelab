# Proxmox host (bare-metal) services

Files deployed onto the hypervisor itself (192.168.1.10), tracked here so the
host can be rebuilt. Containers can't see the host's hardware, so the two
exporters below run as systemd services on bare metal. Prometheus (CT 102,
`proxmox/guests/docker/monitoring.compose.yml`) scrapes them over the bridge.

## node-exporter (:9100)

Hardware + OS metrics: CPU, RAM, disks, temps (hwmon via lm-sensors), SMART
(smartmon.sh textfile collector, cron every 5 min).

Install:

```shell
apt install lm-sensors smartmontools
sensors-detect --auto
useradd -rs /bin/false node_exporter
VER=1.9.1
curl -fsSL https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-amd64.tar.gz \
  | tar -xz -C /tmp
install /tmp/node_exporter-${VER}.linux-amd64/node_exporter /usr/local/bin/
mkdir -p /var/lib/node_exporter/textfile
# from the repo:
scp proxmox/host/node-exporter/node-exporter.service homelab:/etc/systemd/system/
scp proxmox/host/node-exporter/smartmon.sh homelab:/usr/local/bin/
echo '*/5 * * * * root /usr/local/bin/smartmon.sh > /var/lib/node_exporter/textfile/smartmon.prom.tmp && mv /var/lib/node_exporter/textfile/smartmon.prom.tmp /var/lib/node_exporter/textfile/smartmon.prom' > /etc/cron.d/smartmon
systemctl daemon-reload && systemctl enable --now node-exporter
curl -s localhost:9100/metrics | head
```

## prometheus-pve-exporter (:9221)

Per-VM/CT CPU/RAM/disk/uptime and storage pool usage (the local-lvm / local
pressure signals) via the PVE API. Read-only API token, config in `pve.yml`
(ENCRYPTED via transcrypt - carries the token).

Install:

```shell
apt install python3-venv
python3 -m venv /opt/pve-exporter
/opt/pve-exporter/bin/pip install prometheus-pve-exporter
useradd -rs /bin/false pve_exporter
pveum user add prometheus@pve --comment "monitoring read-only"
pveum acl modify / --users prometheus@pve --roles PVEAuditor
pveum user token add prometheus@pve monitoring --privsep 0   # paste value into pve.yml
mkdir -p /etc/prometheus
# from the repo (after filling token_value):
scp proxmox/host/pve-exporter/pve.yml homelab:/etc/prometheus/pve.yml
scp proxmox/host/pve-exporter/prometheus-pve-exporter.service homelab:/etc/systemd/system/
chmod 640 /etc/prometheus/pve.yml && chown root:pve_exporter /etc/prometheus/pve.yml
systemctl daemon-reload && systemctl enable --now prometheus-pve-exporter
curl -s 'localhost:9221/pve?target=localhost' | head
```

Both listen on all interfaces; the LAN is trusted (no port forwarding to the
internet exists). Keep them updated by hand - they are not covered by
unattended-upgrades (static binary + venv).

## Root fs sizing (swap shrunk 2026-06-25)

`local` (pve-root) was 24.9G and chronically near-full: it holds CT 102's two
bind-mount raws (mp0 appdata 8G + mp2 docker 16G = ~24G), leaving almost no room
for image pulls. The VG had 0 free extents, and the `local-lvm` thin pool can't
be shrunk to donate space. Swap was 7.4G but effectively idle (16G RAM box, ~290M
used), so it was shrunk to 2G and the freed extents grew pve-root to 30.3G
(~5.4G more headroom, ~7.8G free after). `vm.swappiness` dropped 60 -> 10
(`/etc/sysctl.d/99-swappiness.conf`). This was done to fit the selkies-desktop
(Webtop) image. fstab references swap by device path (`/dev/pve/swap`), so the
new swap UUID needs no fstab edit.

```
swapoff -a
lvreduce -y -L 2G pve/swap && mkswap /dev/pve/swap && swapon /dev/pve/swap
lvextend -l +100%FREE pve/root && resize2fs /dev/mapper/pve-root
```

## fstrim (daily, 04:30)

`/etc/cron.d/fstrim-ct102` runs `pct fstrim 102` daily. CT 102's mp0/mp2 are
raw files on the root SSD; without trim, deleted blocks stay materialized in
the files and the host root fills. It hit 100% twice: once before the cron
existed (trim reclaimed ~7G), and again on 2026-06-13 despite the then-weekly
cadence (appdata DB churn + watchtower's daily image pulls re-fill ~1GB/day;
trim reclaimed 5.7G). Daily now. The trim also returns rootfs blocks to the
local-lvm thin pool.

```
30 4 * * * root /usr/sbin/pct fstrim 102 >/dev/null
```

## Jellyfin cache prune (daily, 04:15)

`/etc/cron.d/jellyfin-cache-prune` runs `proxmox/scripts/jellyfin-cache-prune.sh`
(deployed to `/usr/local/bin/`) 15 min before the fstrim. Jellyfin's `/config`
lives on the CT 102 appdata loop (`/dev/loop0`, ~7.8G), which is backed by the
host root fs. Jellyfin refuses to start (5XX via caddy) when that loop has under
2GiB free. On 2026-06-24 the host root hit 0 free, the loop starved, and Jellyfin
crash-looped. The script deletes stale transcode segments (untouched >2h, so
active streams survive) and logs older than 14 days; metadata and image cache are
left alone. Running it at 04:15 means the freed blocks are reclaimed by the 04:30
fstrim in the same window.

```
15 4 * * * root /usr/local/bin/jellyfin-cache-prune.sh >/dev/null 2>&1
```
