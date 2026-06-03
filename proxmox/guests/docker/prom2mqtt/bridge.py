"""Prometheus -> Home Assistant MQTT bridge.

Queries a handful of summary expressions from Prometheus and republishes them
to Mosquitto (HA addon) using MQTT discovery, so they show up as entities on a
single "Homelab" device. HA dashboards and automations can then react to infra
health (disk filling, guest down, hot CPU) without HA scraping anything itself.

Config via env: PROM_URL, MQTT_HOST, MQTT_PORT, MQTT_USER, MQTT_PASS,
INTERVAL_SECONDS. This is the spot where Alertmanager would plug in later -
alerts could publish to the same topics.
"""

import json
import os
import time

import paho.mqtt.client as mqtt
import requests

PROM_URL = os.environ.get("PROM_URL", "http://prometheus:9090")
MQTT_HOST = os.environ["MQTT_HOST"]
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_USER = os.environ.get("MQTT_USER")
MQTT_PASS = os.environ.get("MQTT_PASS")
INTERVAL = int(os.environ.get("INTERVAL_SECONDS", "60"))

AVAILABILITY_TOPIC = "homelab/bridge/availability"

# key: (name, unit, device_class, promql)
SENSORS = {
    "host_cpu_percent": (
        "Host CPU",
        "%",
        None,
        '100 - avg(rate(node_cpu_seconds_total{node="proxmox",mode="idle"}[5m])) * 100',
    ),
    "host_temp": (
        "Host temperature",
        "°C",
        "temperature",
        'max(node_hwmon_temp_celsius{node="proxmox"})',
    ),
    "host_mem_percent": (
        "Host memory",
        "%",
        None,
        '(1 - node_memory_MemAvailable_bytes{node="proxmox"}'
        ' / node_memory_MemTotal_bytes{node="proxmox"}) * 100',
    ),
    "root_disk_percent": (
        "Host root disk",
        "%",
        None,
        '100 - node_filesystem_avail_bytes{node="proxmox",mountpoint="/"}'
        ' / node_filesystem_size_bytes{node="proxmox",mountpoint="/"} * 100',
    ),
    "local_lvm_percent": (
        "local-lvm usage",
        "%",
        None,
        'pve_disk_usage_bytes{id=~"storage/.*/local-lvm"}'
        ' / pve_disk_size_bytes{id=~"storage/.*/local-lvm"} * 100',
    ),
    "t7_disk_percent": (
        "T7 usage",
        "%",
        None,
        '100 - node_filesystem_avail_bytes{node="proxmox",mountpoint="/mnt/t7"}'
        ' / node_filesystem_size_bytes{node="proxmox",mountpoint="/mnt/t7"} * 100',
    ),
    "ct102_mem_percent": (
        "Docker LXC memory",
        "%",
        None,
        'pve_memory_usage_bytes{id="lxc/102"} / pve_memory_size_bytes{id="lxc/102"} * 100',
    ),
    "guests_up": (
        "Guests up",
        None,
        None,
        'sum(pve_up{id=~"qemu/100|lxc/101|lxc/102"})',
    ),
    "targets_up": ("Scrape targets up", None, None, "count(up == 1)"),
    "targets_total": ("Scrape targets total", None, None, "count(up)"),
    "minecraft_players": (
        "Minecraft players online",
        None,
        None,
        "sum(minecraft_player_online) or vector(0)",
    ),
}


def query(expr):
    r = requests.get(
        f"{PROM_URL}/api/v1/query", params={"query": expr}, timeout=10
    )
    r.raise_for_status()
    result = r.json()["data"]["result"]
    if not result:
        return None
    return float(result[0]["value"][1])


def publish_discovery(client):
    device = {
        "identifiers": ["homelab_prom2mqtt"],
        "name": "Homelab",
        "manufacturer": "prom2mqtt",
    }
    for key, (name, unit, device_class, _) in SENSORS.items():
        config = {
            "name": name,
            "unique_id": f"homelab_{key}",
            "state_topic": f"homelab/{key}",
            "availability_topic": AVAILABILITY_TOPIC,
            "state_class": "measurement",
            "device": device,
        }
        if unit:
            config["unit_of_measurement"] = unit
        if device_class:
            config["device_class"] = device_class
        client.publish(
            f"homeassistant/sensor/homelab_{key}/config",
            json.dumps(config),
            retain=True,
        )


def main():
    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2, client_id="homelab-prom2mqtt"
    )
    if MQTT_USER:
        client.username_pw_set(MQTT_USER, MQTT_PASS)
    client.will_set(AVAILABILITY_TOPIC, "offline", retain=True)
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=120)
    client.loop_start()
    client.publish(AVAILABILITY_TOPIC, "online", retain=True)
    publish_discovery(client)

    while True:
        for key, (_, _, _, expr) in SENSORS.items():
            try:
                value = query(expr)
            except Exception as exc:  # prometheus down/unreachable
                print(f"query failed for {key}: {exc}")
                continue
            if value is None:
                continue
            client.publish(f"homelab/{key}", round(value, 1))
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
