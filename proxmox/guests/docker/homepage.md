# Homepage dashboard (CT 102)

[Homepage](https://gethomepage.dev) at http://home.home (direct
`http://192.168.1.30:3020`). One tile per service behind Caddy, grouped Media /
Downloads / Books / Knowledge & Tools / Infrastructure. Deployed 2026-10-04.

| Repo | CT 102 |
|---|---|
| `homepage.compose.yml` | `/opt/homepage/compose.yml` |
| `homepage.env` (encrypted) | `/opt/homepage/homepage.env` |
| `homepage/*.yaml` | `/opt/homepage/config/` |

Config lives on the CT rootfs; git is the backup. Homepage reloads YAML changes
on the next page load, no restart needed. Env changes need a recreate (below).

- Tiles open the `.home` name. Status dots and widgets are fetched by the
  homepage container itself: jellystack apps by container name (it joins
  `jellystack_default`), everything else by LAN IP + published port.
- Docker integration is off on purpose (it needs the Docker socket = root on CT 102).

## Credentials

`homepage.env` holds `HOMEPAGE_VAR_*` values that `services.yaml` references.
Filled automatically on 2026-10-04 (read from each app's own config):

| Variable | Source |
|---|---|
| `SONARR_KEY`, `RADARR_KEY`, `LIDARR_KEY`, `PROWLARR_KEY` | `<ApiKey>` in `/mnt/t7/appdata/<app>/config.xml` |
| `SABNZBD_KEY` | `api_key` in `/mnt/t7/appdata/sabnzbd/sabnzbd.ini` |
| `JELLYSEERR_KEY` | `main.apiKey` in `/mnt/t7/appdata/seerr/settings.json` |
| `PROXMOX_USER`, `PROXMOX_TOKEN` | PVE user `homepage@pve`, role PVEAuditor (read-only) on `/`, token `dash` |

Filled by hand (each tile shows "API Error" until set):

| Variable | Where to get it |
|---|---|
| `JELLYFIN_KEY` | Jellyfin -> Dashboard -> API Keys -> `+`, name it `homepage` |
| `ADGUARD_USER` / `ADGUARD_PASS` | the AdGuard web login |
| `QBITTORRENT_USER` / `QBITTORRENT_PASS` | qBittorrent -> Options -> Web UI -> Authentication |
| `NAVIDROME_USER` / `NAVIDROME_TOKEN` / `NAVIDROME_SALT` | a Navidrome user; token = md5(password + salt), see below |
| `GRAFANA_USER` / `GRAFANA_PASS` | Grafana -> Administration -> Users -> New user `homepage`, role Viewer |
| `HOMEASSISTANT_TOKEN` | HA -> your profile -> Security -> Long-lived access tokens -> Create |

Navidrome token on macOS (put the user's password where shown):

```shell
salt=$(openssl rand -hex 6); printf 'salt=%s token=%s\n' "$salt" "$(printf '%s' "PASSWORD$salt" | md5)"
```

Apply after editing `homepage.env`:

```shell
scp proxmox/guests/docker/homepage.env root@192.168.1.30:/opt/homepage/homepage.env
ssh root@192.168.1.30 'docker compose -f /opt/homepage/compose.yml up -d --force-recreate'
```

Before committing, check the staged blob is encrypted:
`git show :proxmox/guests/docker/homepage.env | head -c 8` should print `U2FsdGVk`.

## Adding a tile

Add an entry to `homepage/services.yaml` (icons: names from
[dashboard-icons](https://github.com/homarr-labs/dashboard-icons) or `mdi-*`),
then `scp` it to `/opt/homepage/config/`. Widget types and fields:
https://gethomepage.dev/widgets/.
