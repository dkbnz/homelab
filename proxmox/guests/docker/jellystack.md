# jellystack (CT 102)

The media stack, migrated from a OnePlus phone (postmarketOS + rootless Podman) to
the Docker LXC. Jellyfin and Jellyseerr (each fronted by a Tailscale sidecar),
Sonarr, Radarr, Prowlarr, SABnzbd, gluetun (Surfshark WireGuard) + qBittorrent,
FlareSolverr, Unpackerr, and the music pipeline: Lidarr, slskd (Soulseek, in
gluetun's netns), Soularr, and Navidrome.

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

Jellyfin transcodes with QSV on the host iGPU (UHD 620). The render node is passed
into CT 102 (`dev0: /dev/dri/renderD128,gid=106` in `102-docker.conf`) and into the
jellyfin container (`devices: /dev/dri`). Hardware accel is set to `qsv` in
`appdata/jellyfin/encoding.xml` (decode: h264/hevc/mpeg2/vc1/vp9, 10-bit HEVC yes,
10-bit VP9 no — Kaby Lake can't). Measured ~10x realtime on a 1080p HEVC 10-bit
to h264 transcode.

Jellyfin and Jellyseerr have no host ports — they share their Tailscale sidecar's
network namespace. Reach them over Tailscale (`https://jellyfin.<tailnet>`,
`https://jellyseerr.<tailnet>`) or on the LAN via the Caddy proxy (below). The rest
are on the LAN at `192.168.1.30`: Sonarr `:8989`, Radarr `:7878`, Prowlarr `:9696`,
SABnzbd `:8081`, qBittorrent `:8080` (via gluetun), FlareSolverr `:8191`,
Lidarr `:8686`, Navidrome `:4533`, slskd `:5030` (via gluetun).

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
| `http://lidarr.home`       | `lidarr:8686` |
| `http://navidrome.home`    | `navidrome:4533` |
| `http://slskd.home`        | `gluetun:5030` (slskd shares gluetun's netns) |

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

## Music pipeline (Lidarr + slskd + Soularr + Navidrome)

Request flow: add an artist/album in Lidarr (`http://lidarr.home`). Lidarr tries
usenet/torrents via Prowlarr (qBittorrent + SABnzbd download clients, SAB category
`music`). Whatever the indexers can't find lands on Lidarr's wanted list; Soularr
polls that every 5 minutes, searches Soulseek, downloads via slskd, and triggers
the Lidarr import. Navidrome serves the resulting `/music` library over the
Subsonic API (use Symfonium/play:Sub etc. against `http://navidrome.home`).
Jellyfin also indexes the same folder.

Jellyseerr music requests are **not** wired up: music support only exists in the
experimental `preview-music-support` image, not in stable. Revisit when it ships
in a stable release.

Component notes:

- **slskd** rides gluetun's netns (all Soulseek traffic over the VPN); web/API at
  `:5030` via gluetun's port publish, login `SLSKD_WEB_USER`/`SLSKD_WEB_PASS`.
  The Soulseek account (`SLSK_USER`/`SLSK_PASS`, registered on first login) and
  the rest of its config are env vars in the compose file. The one thing that
  can't be env-configured is the API key Soularr uses - that lives in
  `appdata/slskd/slskd.yml`, rendered from `jellystack/slskd/slskd.yml.tmpl`:

  ```shell
  KEY=$(grep ^SLSKD_API_KEY= jellystack.env | cut -d= -f2)
  sed "s|__SLSKD_API_KEY__|$KEY|" jellystack/slskd/slskd.yml.tmpl > slskd.yml
  # push to /opt/jellystack/appdata/slskd/slskd.yml (chown 10000:10000, chmod 600)
  ```

  slskd shares `/music` back to the Soulseek network read-only (sharing etiquette;
  some peers block leechers). Surfshark has no port forwarding, so no inbound
  Soulseek port - downloads from firewalled peers aren't possible, which costs
  some availability but works fine in practice.
- **Soularr** config is `appdata/soularr/config.ini`, rendered the same way from
  `jellystack/soularr/config.ini.tmpl` (substitutes `__LIDARR_API_KEY__` and
  `__SLSKD_API_KEY__`). slskd completed downloads land in
  `media/downloads/slskd/complete`, which Soularr and Lidarr both see at
  `/downloads/slskd/complete` (same `media/downloads` mount).
- **Lidarr** was wired via API at deploy: root folder `/music` (quality profile
  "Any", metadata "Standard"), qBittorrent + SABnzbd download clients (category
  `music`, creds mirrored from sonarr's DB), and registered as an application in
  Prowlarr (full sync - indexers propagate automatically).
- **Navidrome** admin login is `NAVIDROME_ADMIN_USER`/`NAVIDROME_ADMIN_PASS` in
  `jellystack.env` (stored in Navidrome's own DB; recorded in the env file so it
  isn't lost). Library scans hourly (`ND_SCANSCHEDULE=1h`).

Backups: all four apps keep state under `appdata/` (covered by the daily
`sdc-backup.sh`); the music files themselves are on the T7 and are also in the
backup set (unlike movies/tv). `media/downloads/slskd` is scratch and excluded.

## Still open

- The entire phone-era T7 `media-server/` directory was already removed in the first
  migration. The T7 now holds `jellystack-media/`, `minecraft/`, and PS4 game data,
  all on ext4.
