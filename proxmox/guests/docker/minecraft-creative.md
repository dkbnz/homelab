# minecraft-creative

Throwaway creative Minecraft world for prototyping, on CT 102. Separate from the
real survival server (that one runs off-lab on an external host).

- **Type:** Paper, latest. Superflat (`LEVEL_TYPE=minecraft:flat`), creative,
  peaceful, no mobs/structures, Nether off.
- **Access:** LAN at `192.168.1.30:25565`; reachable over the tailnet via the
  CT 102 subnet router. No public exposure, no router port-forward.
- **Data:** named docker volume `mc-creative-data` on CT 102's `/var/lib/docker`
  (the 16G mp2 raw on `local`). Not on the root fs, not on the T7. Stays small
  because it resets daily.
- **Memory:** 2G heap with Aikar flags.

## Daily reset

The world wipes every day at **09:00 Pacific/Auckland**. Config is kept; only the
blocks reset.

- Script: `proxmox/scripts/mc-creative-reset.sh` -> `/usr/local/bin/mc-creative-reset.sh`
- Cron: `/etc/cron.d/mc-creative-reset`
- It stops the container, deletes `world`/`world_nether`/`world_the_end` from the
  volume, and restarts. itzg regenerates a fresh flat world on boot.
  `server.properties`, `ops.json`, `whitelist.json`, and plugins survive.

Run on demand:

```shell
ssh homelab '/usr/local/bin/mc-creative-reset.sh'
```

## Deploy / redeploy

Compose is not auto-deployed. Copy it in and bring it up:

```shell
# from repo root, push the compose file onto CT 102
cat proxmox/guests/docker/minecraft-creative.compose.yml | \
  ssh homelab 'pct exec 102 -- tee /opt/minecraft-creative/minecraft-creative.compose.yml >/dev/null'
ssh homelab 'pct exec 102 -- docker compose -f /opt/minecraft-creative/minecraft-creative.compose.yml up -d'
```

`watchtower` updates the image daily and prunes old ones.
