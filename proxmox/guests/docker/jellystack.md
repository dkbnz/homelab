# jellystack (CT 102)

The media stack, migrated from a OnePlus phone (postmarketOS + rootless Podman) to
the Docker LXC. Twelve containers: Jellyfin and Jellyseerr (each fronted by a
Tailscale sidecar), Sonarr, Radarr, Prowlarr, SABnzbd, gluetun (Surfshark WireGuard)
+ qBittorrent, FlareSolverr, and Unpackerr.

## Files

- `jellystack.compose.yml` — the compose file (deployed at `/opt/jellystack/compose.yaml`).
- `jellystack.env` — secrets, **encrypted with transcrypt** (WireGuard key, Tailscale
  auth key, Sonarr/Radarr API keys). Deployed at `/opt/jellystack/.env`.
- `jellystack/ts-jellyfin/serve.json`, `jellystack/ts-jellyseerr/serve.json` —
  Tailscale serve config (HTTPS reverse proxy to the app port). Mounted read-only.

App config and databases (the `appdata/` tree) are **not** tracked here — too large
and churny. They live on CT 102 at `/opt/jellystack/appdata` (the mp0 ext4 volume).

## Storage on CT 102

| Path | Backing | Notes |
|------|---------|-------|
| `/opt/jellystack/appdata` | mp0, 8G ext4 on `local` | configs + SQLite DBs + Tailscale state |
| `/opt/jellystack/media`   | mp1, bind of `/mnt/t7/jellystack-media` (T7, ext4) | media (see reconciliation note) |
| `/var/lib/docker`         | mp2, 8G ext4 on `local` | images/layers, kept off the 4G rootfs |

PUID/PGID are `10000` (carried over from the phone). The unprivileged LXC maps
container `10000` to host `110000`; media files on the T7 are owned `110000:110000`
so the containers (uid `10000` inside) can write to them. The T7 is ext4 (mounted by
UUID via `/etc/fstab`), so ownership is stored on disk — no forced mount uid/gid.

## Deploy

```shell
ssh homelab 'pct exec 102 -- docker compose -f /opt/jellystack/compose.yaml up -d'
```

Jellyfin and Jellyseerr have no host ports — they share their Tailscale sidecar's
network namespace. Reach them over Tailscale (`https://jellyfin.<tailnet>`,
`https://jellyseerr.<tailnet>`) or on the LAN via the Caddy proxy (below). The rest
are on the LAN at `192.168.1.30`: Sonarr `:8989`, Radarr `:7878`, Prowlarr `:9696`,
SABnzbd `:8081`, qBittorrent `:8080` (via gluetun), FlareSolverr `:8191`.

## Local access (Caddy + AdGuard)

The `caddy` service publishes `:80` on the docker host and routes every app by
hostname. The `caddy/Caddyfile` maps:

| URL | Upstream |
|-----|----------|
| `http://jellyfin.home`     | `jellyfin:8096` |
| `http://jellyseerr.home`   | `jellyseerr:5055` |
| `http://sonarr.home`       | `sonarr:8989` |
| `http://radarr.home`       | `radarr:7878` |
| `http://prowlarr.home`     | `prowlarr:9696` |
| `http://sabnzbd.home`      | `sabnzbd:8080` |
| `http://qbittorrent.home`  | `gluetun:8080` (qBittorrent shares gluetun's netns) |
| `http://flaresolverr.home` | `flaresolverr:8191` |

Name resolution is via an **AdGuard Home wildcard DNS rewrite** (`*.home` ->
`192.168.1.30`, see `proxmox/guests/adguard/AdGuardHome.yaml`), so any new `.home`
name routes to Caddy automatically. This only works for clients that use AdGuard
(`192.168.1.20`) as their resolver. `.home` is used rather than `.local` because
`.local` is mDNS-only and not resolvable via unicast DNS on Apple devices.

Host-header validation notes: SABnzbd rejects unknown `Host` headers, so
`sabnzbd.home` is added to its `host_whitelist` (in `appdata/sabnzbd/sabnzbd.ini`).
qBittorrent accepted the proxied host as-is. Only Jellyfin and Jellyseerr are exposed
over Tailscale (they're the only services with a `ts-*` sidecar); everything else is
LAN-only via Caddy.

## Tailscale

This stack uses **Tailscale SaaS** (tailnet `shetland-gamma.ts.net`), not the repo's
headscale server. The sidecar state was copied with the rest of `appdata`, so the
`jellyfin` and `jellyseerr` nodes rejoined with their existing identities, no re-auth.

## Media + library reconciliation (done)

The phone's library (~63GB) was copied over the LAN into `/mnt/t7/jellystack-media/`
(`tv`, `movies`, `downloads`), matching the paths the migrated *arr configs expect
(`/tv`, `/movies`, `/downloads`). After rescans, the libraries line up across the
stack: Radarr 10/12 movies, Sonarr 16/18 episodes (the gaps are in-progress
downloads), and Jellyfin reports the same (10 movies, 1 series, 16 episodes).

Download-pipeline config that did not survive the Podman->Docker move and was fixed
on the live stack (all in SABnzbd / the *arr download-client settings, stored in
`appdata`, not tracked here):

- SABnzbd `host_whitelist` now includes `sabnzbd` (the container name the *arr apps
  use) - it was rejecting requests with 403.
- Sonarr/Radarr SABnzbd **API key** updated to SABnzbd's actual key (the migrated key
  was stale).
- Sonarr/Radarr SABnzbd **categories** set to `tv` / `movies` (the configured
  `tv-sonarr` / `movies-radarr` don't exist in this SABnzbd).
- SABnzbd `complete_dir`/`download_dir` repointed to the shared `/downloads` mount
  (they were relative paths resolving inside SABnzbd's own `/config`).

## T7 media-server library folded in (done)

The T7's older `media-server/library` (17 movies + Lucky Hank) was moved into the
stack's tree (`mv` within the same exfat filesystem - instant, no copy): movies into
`jellystack-media/movies`, `shows` into `jellystack-media/tv`. No name collisions
with the phone's library. Then imported:

- Radarr: 17 movies added via API (Import Existing); 27/29 movies now have files
  (the 2 without are pre-existing wanted entries from the phone).
- Sonarr: Lucky Hank added (8/8 episodes); The Rookie still 16/18.
- Jellyfin: rescanned - 27 movies, 2 series, 24 episodes.
- Jellyseerr: full + Radarr/Sonarr scans run - 27 available items synced.

One metadata fix: the "Mean Girls (2024)" folder first matched TMDB's 2004 film
(lookup takes the first result); corrected to the 2024 entry.

## Prowlarr indexers (mostly resolved)

Most of the "unavailable" indexers were stale failures - they passed on retest.
The FlareSolverr indexer proxy (already configured at `http://flaresolverr:8191/`,
tag `cloudflare` id 1) wasn't being applied because the CloudFlare indexers had no
tags. Tagged `0Magnet` and `kickasstorrents.ws` with `cloudflare`; **12/14 indexers
now valid**. 0Magnet now passes through FlareSolverr.

`kickasstorrents.ws` was **disabled** - FlareSolverr can't solve its CloudFlare
challenge (Turnstile; a dead KAT mirror). `Internet Archive` stays enabled but
intermittently times out (a slow but legitimate site, not a block). Sonarr may
briefly still warn about `1337x`/`Internet Archive`; those are cached failure records
that age out of its 6-hour window once queries succeed - Prowlarr tests 1337x valid.

A full VPN reroute of Prowlarr through gluetun was considered and skipped: the other
indexers resolve directly, and neither remaining failure is an IP-block, so it would
add risk (compose change, gluetun firewall ports, breaks the `prowlarr` hostname for
inter-container calls) with no benefit.

## T7 converted exfat -> ext4 (done)

The T7 was reformatted from exFAT to ext4 so the *arr apps get real Unix ownership
and hardlinks (exFAT forces a single mount uid/gid and can't hardlink, which breaks
atomic import moves). exFAT has no shrink tool, so the convert needed a full evac:

1. Attached a 465GB ext4 USB disk (`sdc`, mounted `/mnt/sdc`, ~328GB free).
2. `rsync` the entire T7 (164GB: jellystack-media + PS4 `CUSA00473` + minecraft +
   itemzflow) to `/mnt/sdc/t7-staging` as a full backup; verified file counts.
3. `mkfs.ext4 /dev/sdb1`; updated `/etc/fstab` to mount the new ext4 UUID at `/mnt/t7`
   (dropped the old `uid=/gid=/umask=` exFAT mount options).
4. `rsync` everything back. Files keep `110000:110000` ownership (= container 10000).

The `/mnt/sdc/t7-staging` copy served as the backup during the convert and was wiped
afterwards. sdc now holds the daily `sdc-backup.sh` backup of appdata + the minecraft
world + PS4 data; the raw video media is deliberately not backed up (redownloadable).
mp1 (jellystack-media) and mp3 (minecraft) are path-based binds, so they survived the
reformat unchanged.

## Second fold: old 2023 sdc library (done)

The `sdc` disk also carried an older 2023 media-server backup. Its library was folded
into the stack (`rsync --ignore-existing`, so the existing jellystack copies win),
following the same paths/naming: `data/movies -> movies`, `data/series -> tv`,
`data/music -> music`. Added:

- Radarr: Me Before You (2016), The Little Mermaid (2023), The Menu (2022) - all
  imported with files (A Man Called Otto was already present, skipped as a dupe).
- Sonarr: StartUp (20/30 eps) and The Last of Us (9/16 eps) - partial seasons, since
  the old library only had those episodes.
- Jellyfin: music library populated (Adele, Lewis Capaldi, Tom Walker) plus the new
  movies/series; full library rescan run.

## Still open

- The entire phone-era T7 `media-server/` directory was already removed in the first
  migration. The T7 now holds `jellystack-media/`, `minecraft/`, and PS4 game data,
  all on ext4.
