# Valheim on CT 102

> Removed from CT 102 on 2026-10-04 (container and image deleted). The world is
> still on the T7 at `/mnt/t7/valheim` (CT 102 mp7) and in the SD card backup.
> Redeploy with the steps below.

Valheim dedicated server running natively on x86_64 with PlayFab crossplay.
Image: `ghcr.io/lloesche/valheim-server`. Deployed 2026-10-03.

The same world also runs on the OCI Arm box (`dkbnz/dogs-and-bogs`, `/opt/valheim`),
where the x86_64-only server binary runs under box64 and segfaults every day or two.
On this host the server runs without emulation.

## Layout

| Host path                     | CT 102 path                    | Container path  | Contents |
|-------------------------------|--------------------------------|-----------------|----------|
| `/mnt/t7/valheim/config`      | `/opt/valheim/data/config`     | `/config`       | `worlds_local/`, adminlist, permittedlist, `backups/` |
| `/mnt/t7/valheim/server`      | `/opt/valheim/data/server`     | `/opt/valheim`  | game files from steamcmd (~2 GB) |

- CT 102 bind mount: `mp7: /mnt/t7/valheim,mp=/opt/valheim/data` (hotplugged, no CT restart).
- Owned by host uid/gid 110000 (container 10000, `PUID`/`PGID` in compose).
- `sdcard-backup.sh` mirrors `config/` (worlds + the image's hourly zips) and skips `server/`.
- Compose and env in CT 102: `/opt/valheim/compose.yml`, `/opt/valheim/valheim.env`.

## Joining

`-crossplay` puts the server on PlayFab instead of the Steam socket. Players join by
6-digit join code (Join Game > Join by code). There is no direct IP join and no
server browser entry. No port forwarding: PlayFab relays through Starlink's CGNAT.

The join code is only in the log. Read it, don't copy it from here:

```shell
ssh homelab 'pct exec 102 -- docker logs valheim 2>&1 | grep -a "join code" | tail -1'
```

The code can change when the server restarts (game update, image recreate, crash).

## World

`Berwick`, copied from the OCI server on 2026-10-03 03:22 NZ (save `_main.642`,
md5 of `_main.642.db2` matched on both ends). From that point the two copies diverge.
Players should only use one server. To move the world again, stop the source
server first so it saves, then tar `worlds_local/Berwick` across.

Modifiers (`resources muchmore`, `portals casual`) are passed in `SERVER_ARGS` to
match OCI. They are also stored in the world.

## Operations

```shell
ssh homelab 'pct exec 102 -- docker compose -f /opt/valheim/compose.yml up -d'
ssh homelab 'pct exec 102 -- docker logs --tail 50 valheim'
ssh homelab 'pct exec 102 -- docker restart valheim'     # saves on stop
```

- Game updates: the image checks at 05:00 daily (`UPDATE_CRON`) and only restarts
  when nobody is connected (`UPDATE_IF_IDLE`).
- Watchtower is off for this container (label), so the image itself is updated by
  hand: `docker compose pull && docker compose up -d`.
- Backups: hourly zip to `/config/backups`, newest 24 kept.
- Limits: 3 CPUs, 6 GB RAM.
