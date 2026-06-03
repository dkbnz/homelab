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
