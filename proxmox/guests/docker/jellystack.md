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
| `/opt/jellystack/media`   | mp1, bind of `/mnt/t7/jellystack-media` (T7, exfat) | media (see reconciliation note) |
| `/var/lib/docker`         | mp2, 8G ext4 on `local` | images/layers, kept off the 4G rootfs |

PUID/PGID are `10000` (carried over from the phone). The unprivileged LXC maps
container `10000` to host `110000`; the T7 is mounted with `uid=110000,gid=110000`
so the containers can write to it.

## Deploy

```shell
ssh homelab 'pct exec 102 -- docker compose -f /opt/jellystack/compose.yaml up -d'
```

Jellyfin and Jellyseerr have no host ports — reach them only over Tailscale
(`https://jellyfin.<tailnet>`, `https://jellyseerr.<tailnet>`). The rest are on the
LAN at `192.168.1.30`: Sonarr `:8989`, Radarr `:7878`, Prowlarr `:9696`,
SABnzbd `:8081`, qBittorrent `:8080` (via gluetun), FlareSolverr `:8191`.

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

## Still open

- Several public Prowlarr indexers (1337x, The Pirate Bay, NZBgeek, Nyaa.si,
  Internet Archive) report unavailable. Prowlarr reaches indexers directly, not
  through the VPN, so these are likely ISP-blocked. Option: route Prowlarr through
  gluetun, or use FlareSolverr consistently.
- The T7's separate older `media-server/` library (~170GB) is still present and
  unused by this stack; fold it in or leave it.
- Convert the T7 to ext4 once a spare >=200GB disk is available to stage its data.
