# Home Assistant OS (VM 100)

Home Assistant runs as an appliance VM (HAOS), built via the community Proxmox
helper script. Most of its config lives inside the VM and is backed up by HA's own
snapshot mechanism, not this repo. Automations that are worth version-controlling are
captured here.

## Access

- HAOS host shell: `ssh homelab 'qm guest exec 100 -- /bin/sh -c "<cmd>"'`
  (qemu-guest-agent is enabled). Output comes back as `{"out-data": "..."}` JSON.
- The HA config dir is on the HAOS host at
  `/mnt/data/supervisor/homeassistant/` (e.g. `automations.yaml`, `.storage/`).
- The HA container is reachable as `docker exec homeassistant ...` from the HAOS host
  (useful for reading the recorder DB at `/config/home-assistant_v2.db`).
- `ha core check` validates config; `ha core restart` reloads it.

## Key integrations / devices

- **Starlink** integration: throughput/ping/power sensors
  (`sensor.starlink_downlink_throughput`, `sensor.starlink_uplink_throughput`, ... in
  Mbit/s), plus a native `switch.starlink_sleep_schedule`.
- **Zigbee2MQTT** + Mosquitto addons: two Tuya power-monitoring smart plugs,
  `switch.0xa4c138ef31102dc3` and `switch.0xa4c1380d7c843043`, that power the internet.
- ESPHome, HACS addons.

## Tracked automations

- `internet-idle-automation.yaml` — cut the internet plugs when Starlink is idle
  after midnight, restore at 07:00. Coexists with the in-HA presence automations
  (`presence_plug_off` / `presence_plug_on`) on the same plugs; see the file header.

## Tracked config blocks

- `prometheus-config.yaml` — `prometheus:` integration block appended to
  `configuration.yaml`. Prometheus on CT 102 scrapes `/api/prometheus` with a
  long-lived token; prom2mqtt pushes infra summary sensors back in via
  Mosquitto. See `proxmox/guests/docker/monitoring.md`.
- `http-config.yaml` — `http:` block trusting Caddy on CT 102 as a reverse
  proxy, so http://homeassistant.home works (without it HA 400s proxied
  requests).

To change one: edit the live `automations.yaml`, `ha core check`, `ha core restart`,
then mirror the change back here.
