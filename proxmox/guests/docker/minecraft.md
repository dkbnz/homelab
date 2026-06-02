# Minecraft server (CT 102)

Paper server in Docker on the Docker LXC. World data on the Samsung T7.

## What runs

- Container `minecraft`, image `itzg/minecraft-server:java25`, Paper, 3 GB heap, Aikar flags.
- Compose: `minecraft.compose.yml` (deployed at `/opt/minecraft/minecraft.compose.yml` in CT 102).
- World data: `/opt/minecraft/data` in the container, backed by `/mnt/t7/minecraft` on the host (mp3).
- Listens on `192.168.1.30:25565` (LAN only — no router port-forward).

## Storage / permissions

The T7 is ext4 (host `/mnt/t7`, mounted by UUID via `/etc/fstab`). World files are
owned `110000:110000` on the host, which the unprivileged LXC maps to uid/gid
`10000`, so the server runs as `UID=10000 GID=10000` to own its files. ext4 gives
real POSIX locking and perm bits (unlike the T7's former exFAT), so the world dir
behaves normally. Still never run two servers against one world dir.

## Deploy / update

```shell
# edit minecraft.compose.yml, then push + up:
cat proxmox/guests/docker/minecraft.compose.yml | ssh homelab \
  'cat > /tmp/mc.yml && pct push 102 /tmp/mc.yml /opt/minecraft/minecraft.compose.yml && \
   pct exec 102 -- docker compose -f /opt/minecraft/minecraft.compose.yml up -d'
```

Console / ops:

```shell
ssh homelab 'pct exec 102 -- docker logs --tail 50 minecraft'
ssh homelab 'pct exec 102 -- docker exec -i minecraft rcon-cli'   # server console
ssh homelab 'pct exec 102 -- docker exec minecraft mc-monitor status --host localhost'
```

`VERSION: LATEST` re-resolves the Paper build on each container (re)start. Pin it to
a fixed version once players settle so a restart can't bump MC out of client compat.
`watchtower` updates the itzg image daily; it does not change the resolved MC version
unless the container restarts with `VERSION: LATEST`.

## Public access via GCP (relay, no port-forward)

The home rule is no router port-forward. Expose the server by relaying TCP 25565
through the existing GCP box (public IP, already runs Headscale) down the existing
WireGuard/Headscale link to `192.168.1.30:25565`.

Sketch (on the GCP VM):

```shell
# forward public :25565 to the home Docker LXC over the tunnel
# socat (simple) or nftables DNAT, or frp. Example with socat as a unit:
socat TCP-LISTEN:25565,fork,reuseaddr TCP:192.168.1.30:25565
```

Then DNS: `A minecraft.dkb.nz -> <GCP public IP>` (Cloudflare grey-cloud / unproxied;
Cloudflare's HTTP proxy can't carry Minecraft TCP). Optionally an SRV record
`_minecraft._tcp.minecraft.dkb.nz` so players can type the bare hostname on odd ports.

Open TCP 25565 on the GCP firewall (terraform) for the relay to be reachable.
