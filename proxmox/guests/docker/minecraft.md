# Minecraft server (CT 102)

Paper server in Docker on the Docker LXC. World data on the Samsung T7.

## What runs

- Container `minecraft`, image `itzg/minecraft-server:java25`, Paper, 3 GB heap, Aikar flags.
- Compose: `minecraft.compose.yml` (deployed at `/opt/minecraft/minecraft.compose.yml` in CT 102).
- World data: `/opt/minecraft/data` in the container, backed by `/mnt/t7/minecraft` on the host (mp3).
- Listens on `192.168.1.30:25565` (Java, TCP) and `192.168.1.30:19132/udp` (Bedrock via
  Geyser). LAN only — no router port-forward.

## Bedrock crossplay (Geyser + Floodgate)

Geyser-Spigot translates Bedrock clients to the Java server; Floodgate lets them join
without a Java account (they appear with a `.` username prefix). Both jars are
re-downloaded from the GeyserMC latest-build URLs on each container (re)start via the
itzg `PLUGINS` env, so they track upstream — needed because Geyser updates frequently
for new Bedrock client versions, and pairs with `VERSION: LATEST` for Paper.

- Bedrock port: UDP 19132. Published on the LAN by the sidecar; tailnet clients reach
  it directly (Tailscale carries UDP) at the sidecar's tailnet IP.
- Public Bedrock access rides the Oracle relay (see below), UDP 19132.
- Config: `/data/plugins/Geyser-Spigot/config.yml`, `auth-type: floodgate`. Config
  edits apply with `geyser reload` from the console, no server restart.
- Plugin load itself needs a server restart (Paper has no hot plugin load).

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

## Public access via Oracle relay (no port-forward)

The home rule is no router port-forward. The old GCP relay is decommissioned. Public
access goes through the OCI k3s cluster (ap-melbourne-1): a relay pod on `k3s-control`
(public IP `161.33.75.89`) joins the tailnet as `mc-relay` and socat-forwards down to
the minecraft sidecar (`100.66.124.27`):

- TCP 25565 (Java) and UDP 19132 (Bedrock/Geyser), exposed via hostPort.
- Manifest: `k8s/mc-relay/mc-relay.yaml` (this repo; applied with kubectl, not ArgoCD).
- Secret `mc-relay/ts-authkey` created out-of-band from `minecraft.env`'s TS_AUTHKEY.
- OCI side: the "Minecraft" NSG (ingress TCP 25565 + UDP 19132 from 0.0.0.0/0) is
  attached to the k3s-control VNIC.
- DNS: `A minecraft.dkb.nz -> 161.33.75.89` (OnlyDomains, hand-managed).

This replaced the dedicated `mc-relay-mel` E2.1.Micro VM (2026-06-04): its 47 GB boot
volume pushed total OCI block storage to 247 GB, over the 200 GB always-free cap.
Decommission it once DNS has cut over (instance + boot volume) to get back to $0.

Resource cost on the cluster: requests 30m CPU / 64Mi across the three containers
(tailscale + 2x socat), limits 600m / 256Mi.
