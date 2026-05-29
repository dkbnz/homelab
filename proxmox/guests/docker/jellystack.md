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

## Media reconciliation (pending)

Migrated with config only; media was left behind. The T7 already holds a separate
older `media-server/` library (~170GB) with its own *arr databases. The *arr apps
here catalog the phone's library, so their items show as "missing" until the media is
reconciled. Follow-ups: copy the phone's library and/or repoint the *arr root folders
at the T7's existing `media-server/library`, and convert the T7 to ext4 once a spare
disk is available to stage its 183GB.
