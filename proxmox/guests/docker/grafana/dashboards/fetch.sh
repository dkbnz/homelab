#!/usr/bin/env bash
# Fetch the pinned community dashboards into this directory so Grafana can
# file-provision them (see ../provisioning/dashboards/dashboards.yml).
# The JSONs are committed to the repo - rerun this only to bump revisions.
#
# Downloaded dashboards reference a templated datasource (${DS_PROMETHEUS});
# file-provisioned dashboards skip the import wizard, so we hard-replace it
# with the provisioned datasource uid ("prometheus").
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

grafana_com() { # id rev outfile
  curl -fsSL "https://grafana.com/api/dashboards/$1/revisions/$2/download" -o "$3"
}

# grafana.com community dashboards (id, pinned revision)
grafana_com 1860  37 node-exporter-full.json        # Node Exporter Full
grafana_com 10347 5  proxmox-pve.json               # Proxmox via Prometheus (pve-exporter)
grafana_com 14282 1  cadvisor.json                  # cAdvisor exporter
grafana_com 13330 2  adguard.json                   # AdGuard exporter (ebrianne)

# project-shipped dashboards (pinned to a commit where possible)
curl -fsSL https://raw.githubusercontent.com/onedr0p/exportarr/master/examples/grafana/dashboard.json -o exportarr.json
curl -fsSL https://raw.githubusercontent.com/esanchezm/prometheus-qbittorrent-exporter/master/grafana/dashboard.json -o qbittorrent.json
# homelab-overview.json is authored in-repo; fetch.sh must not clobber it.

# normalise the templated datasource to the provisioned uid
for f in node-exporter-full.json proxmox-pve.json cadvisor.json adguard.json exportarr.json qbittorrent.json; do
  sed -i.bak -E 's/\$\{?DS_PROMETHEUS\}?/prometheus/g; s/\$\{?DS_VICTORIAMETRICS\}?/prometheus/g' "$f"
  rm -f "$f.bak"
done

echo "done: $(ls *.json | wc -l | tr -d ' ') dashboards"
