# Project Zomboid on CT 102

Build 42 dedicated server, deployed 2026-10-09. Image
`danixu86/project-zomboid-dedicated-server:latest` (game files baked into the
image, tagged per release, e.g. `42.21-release-2`). Runs natively on x86_64.

It replaced the Zomboid server on the OCI Arm box (`dkbnz/dogs-and-bogs`), which
ran the x86 JVM under FEX and crashed (SIGSEGV) within hours of first players.
That box now only relays the game ports here, so the public address did not
change: players still join `play.dkb.nz:16261`.

## Path

```
player -> play.dkb.nz (159.13.57.100) :16261-16262/udp
       -> OCI iptables DNAT + MASQUERADE -> tailscale0 (node pz-relay, tag:pz-relay)
       -> zomboid node 100.92.78.99 (ts-zomboid sidecar on CT 102)
       -> zomboid container (shares ts-zomboid's netns)
```

- No port forwarding at home. The only path from the internet in is the relay,
  and the tailnet policy lets `tag:pz-relay` reach nothing but
  `zomboid` on `udp:16261-16262` (policy `tests` block checks this on save).
- The relay connects directly to home over WireGuard (OCI and Starlink both
  have easy NAT; `41641/udp` is open in OCI iptables). If `tailscale ping`
  from OCI shows `via DERP(syd)`, add `41641/udp` to the OCI NSG too.
- Latency: OCI Sydney <-> home is ~60 ms. A NZ player sees roughly 100 ms.
  From inside the home LAN, use `192.168.1.30:16261` instead of `play.dkb.nz`
  (the public path hairpins to Sydney and back, ~130 ms).
- The server sees every relayed player as the relay's tailnet IP
  (100.71.146.103). IP bans are useless; ban by username/Steam ID.

## Layout

| Host path                     | CT 102 path                    | Container path | Contents |
|-------------------------------|--------------------------------|----------------|----------|
| `/mnt/t7/zomboid/server`      | `/opt/zomboid/data/server`     | `/home/steam/Zomboid` | `Server/homelab.ini`, SandboxVars, `Saves/`, `db/`, `Logs/`, `backups/` |
| `/mnt/t7/zomboid/workshop`    | `/opt/zomboid/data/workshop`   | `.../steamapps/workshop` | workshop mods (redownloadable, not backed up) |
| `/mnt/t7/zomboid/tailscale`   | `/opt/zomboid/data/tailscale`  | `/var/lib/tailscale` (ts-zomboid) | node state; losing it means re-login |

- CT 102 bind mount `mp12: /mnt/t7/zomboid,mp=/opt/zomboid/data` (hotplugged).
- Owned by host uid 100000 (container root). The image runs as root and
  chowns its data to its `steam` user itself. Directories created on the host
  must be chowned to 100000 or tailscaled can't write its state.
- Compose and env in CT 102: `/opt/zomboid/compose.yml`, `/opt/zomboid/zomboid.env`.

## Settings

- `SERVERNAME=homelab`, not public, password-gated. Players pick their own
  username/password on first join.
- `PASSWORD` in `zomboid.env` matches the old OCI server, so the join info the
  gamekeeper bot posts in Discord is still right.
- `ADMINPASSWORD` is only read on the first start (creates `admin`).
- Sandbox options: edit `server/Server/homelab_SandboxVars.lua`, then restart.
- Memory: 4 GB heap (`MIN_MEMORY`/`MAX_MEMORY`), `mem_limit: 6g`. The image uses
  ZGC, which maps the heap through memfd, so the heap shows as `shmem` in
  `free`/cgroup stats, not as anon.

## Tailscale login

`ts-zomboid` has no auth key. Containerboot gives `tailscale up` 60 s, then exits,
and the container restarts with a fresh login URL, so a URL can't be approved
in time. If the state is lost, log in with a helper that waits:

```shell
docker compose -f /opt/zomboid/compose.yml stop
docker run -d --rm --name ts-zomboid-login -v /opt/zomboid/data/tailscale:/var/lib/tailscale \
  tailscale/tailscale:latest tailscaled --statedir=/var/lib/tailscale --tun=userspace-networking
docker exec ts-zomboid-login tailscale up --hostname=zomboid --accept-dns=false --timeout=0
# approve the URL, then:
docker stop ts-zomboid-login && docker compose -f /opt/zomboid/compose.yml up -d
```

Delete the old `zomboid` machine in the admin console first, or the new one
comes up as `zomboid-1` with a new IP (and the policy `hosts` entry and the
OCI DNAT target both point at 100.92.78.99). Key expiry is disabled on the node.

## Operations

```shell
ssh homelab 'pct exec 102 -- docker logs --tail 50 zomboid'
ssh homelab 'pct exec 102 -- docker compose -f /opt/zomboid/compose.yml restart zomboid'   # saves on stop
ssh -i ~/.ssh/mc-oci ubuntu@159.13.57.100 'sudo tailscale ping -c 3 100.92.78.99'      # relay path
```

- Startup to `*** SERVER STARTED ***` takes about 90 s.
- Updates: watchtower pulls new image tags at 04:00, which restarts the server.
  Clients auto-update through Steam and must match the server build, so this
  stays on.
- Backups: `sdcard-backup.sh` mirrors `/mnt/t7/zomboid` except `workshop/`.
- Health check without a client: a RakNet unconnected ping to `16262/udp`
  answers with `0x1c` (16261 is Steam networking and does not answer it).
