# Monitoring stack (CT 102)

Prometheus + Grafana + exporters covering hardware -> hypervisor -> guests ->
containers -> applications -> Home Assistant. See `monitoring.compose.yml` for
the service list and `proxmox/host/README.md` for the bare-metal host exporters.

## Layout

| Where | What |
|-------|------|
| Proxmox host (.10) | node_exporter :9100, prometheus-pve-exporter :9221 (systemd, `proxmox/host/`) |
| CT 102 `/opt/monitoring` | this stack: Prometheus :9090, Grafana :3000, cadvisor, node-exporter, exportarr x4, adguard-exporter, minecraft-exporter :9150 (host netns), prom2mqtt |
| jellystack | qbittorrent-exporter (gluetun netns, :8090), Jellyfin native /metrics, Caddy admin /metrics :2019 |
| watchtower | metrics API :8085 (token in `watchtower.env`) |
| HAOS VM (.40) | scraped at `/api/prometheus` (long-lived token); Mosquitto receives prom2mqtt sensors |

TSDB + Grafana data live on the T7 via CT 102's `mp4` bind
(`/mnt/t7/monitoring` -> `/opt/monitoring/data`) - the local SSD has no
headroom. Retention: 90d / 40GB cap.

URLs (LAN, via AdGuard `*.home` -> .30): http://grafana.home,
http://prometheus.home (also :3000 / :9090 direct). Grafana login:
`GF_SECURITY_ADMIN_USER`/`GF_SECURITY_ADMIN_PASSWORD` in `monitoring.env`.

## Deploy

```shell
# 0) one-time: host exporters (see proxmox/host/README.md), then
ssh homelab 'mkdir -p /mnt/t7/monitoring/{prometheus,grafana} && chown -R 110000:110000 /mnt/t7/monitoring'
ssh homelab 'pct set 102 -mp4 /mnt/t7/monitoring,mp=/opt/monitoring/data'   # needs CT restart

# 1) copy the stack in (rsync to the host, then into the CT via /proc rootfs or pct push)
rsync -a proxmox/guests/docker/{monitoring.compose.yml,monitoring.env,prometheus,grafana,prom2mqtt} homelab:/tmp/monitoring/
ssh homelab 'pct exec 102 -- mkdir -p /opt/monitoring && pct push 102 ... '   # see jellystack.md for the pattern

# 2) secrets: prometheus reads token files, not env
ssh homelab 'pct exec 102 -- sh -c "mkdir -p /opt/monitoring/secrets && cd /opt/monitoring && \
  grep ^HA_PROMETHEUS_TOKEN= monitoring.env | cut -d= -f2 > secrets/ha.token && \
  grep ^WATCHTOWER_TOKEN= monitoring.env | cut -d= -f2 > secrets/watchtower.token && \
  chown -R 10000:10000 secrets && chmod 600 secrets/*"'

# 3) up
ssh homelab 'pct exec 102 -- docker compose -f /opt/monitoring/monitoring.compose.yml --env-file /opt/monitoring/monitoring.env up -d --build'
```

Then check http://prometheus.home/targets - everything should be UP.

## Per-app metric enablement (one-time)

- **Jellyfin**: native metrics; set `<EnableMetrics>true</EnableMetrics>` in
  `/opt/jellystack/appdata/jellyfin/data/config/system.xml` (inside the
  `<ServerConfiguration>` block) and restart the container. Endpoint is
  unauthenticated at `jellyfin:8096/metrics` - LAN/tailnet only, acceptable here.
- **Caddy**: `admin :2019` + `servers { metrics }` in the Caddyfile (done).
- **Watchtower**: `WATCHTOWER_HTTP_API_METRICS` + token (done; redeploy watchtower).
- **qBittorrent**: exporter needs the WebUI login in `jellystack.env`
  (`QBIT_USER`/`QBIT_PASS`), or tick "Bypass authentication for clients on
  localhost" in qBit options and leave them blank.
- **AdGuard**: exporter uses the web UI login (`ADGUARD_USER`/`ADGUARD_PASS` in
  `monitoring.env`).
- **Home Assistant**:
  1. Append `proxmox/guests/haos/prometheus-config.yaml` to HA's
     `configuration.yaml`, `ha core check && ha core restart`.
  2. Create a long-lived token (profile -> Security) -> `HA_PROMETHEUS_TOKEN`
     in `monitoring.env`, regenerate `secrets/ha.token`.
  3. HAOS is DHCP at 192.168.1.40 - give it a router reservation so the scrape
     target stays valid.
  4. Mosquitto login for prom2mqtt -> `MQTT_USER`/`MQTT_PASS` in `monitoring.env`.
     The broker side is the `logins:` section of the Mosquitto **addon config**
     (HA -> Settings -> Add-ons -> Mosquitto -> Configuration; user
     `observability`), not an HA user account. Addon restart applies it.
     The bridge publishes MQTT-discovery sensors that appear as a "Homelab"
     device in HA (host CPU/temp/mem, root + local-lvm + T7 disk %, CT 102 mem,
     guests up, scrape targets up, Minecraft players).

## Dashboards

File-provisioned from `grafana/dashboards/` (pinned JSONs, committed).
`fetch.sh` re-downloads the community ones; `minecraft.json` and
`homelab-overview.json` are authored in-repo. The provisioning folder is
"Homelab"; UI edits to provisioned dashboards don't persist across restarts
unless exported back into the repo.

## Updates

Prometheus + Grafana are version-pinned and labelled
`com.centurylinklabs.watchtower.enable=false` - bump them deliberately by
editing the compose file. All exporters float on `:latest` under watchtower.

## Alerting (not built)

When wanted: add Alertmanager to this compose file, point Prometheus at it,
and route notifications to Discord (webhook) and/or the same MQTT topics
prom2mqtt uses so HA automations can react.
