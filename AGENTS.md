# AGENTS.md

Operating guide for managing this homelab as infrastructure-as-code. This repo is
the source of truth for a Proxmox-based home server. The intent is to manage the
infrastructure end-to-end through an agent, so this file documents the topology,
access, conventions, and workflows needed to do that safely.

## What this is

A single mini PC running Proxmox VE 8.4, hosting one VM and two LXC containers.
The repo captures the host and guest state declaratively, encrypts secrets in place
(public repo), and provides scripts to reconcile live state back into git.

## Topology

Host `proxmox` at `192.168.1.10/24`, gateway `192.168.1.1`, single bridge `vmbr0`
on `eno0`. Onboard WiFi disabled.

| ID  | Type | Name     | Address          | Purpose                                  |
|-----|------|----------|------------------|------------------------------------------|
| 100 | VM   | haos12.4 | DHCP             | Home Assistant OS 12.4 (Zigbee + BT USB) |
| 101 | LXC  | adguard  | `192.168.1.20`   | AdGuard Home DNS / ad blocking           |
| 102 | LXC  | docker   | `192.168.1.30`   | Docker host (watchtower + service stacks)|

Hardware: Intel i7-8650U, 16 GB RAM. 64 GB SanDisk SSD (boot, `local`,
`local-lvm`); 931 GB Samsung T7 (**ext4**, mounted `/mnt/t7`, on a USB3 SuperSpeed
port; bound into CT 102 as mp0 `appdata` + mp1 `jellystack-media` + mp2 `docker` +
mp4 `monitoring` + mp5 `books` + mp6 `desktop` + mp7 `valheim` (stopped, world kept) +
mp8 `archive` + mp9 `nanobot` (retired, stopped) + mp10 `vault` + mp11 `hermes` + mp12 `zomboid`); 953 GB onboard SD card (ext4,
mounted `/mnt/sdcard`; holds the daily `sdcard-backup.sh` backup of the irreplaceable
data - see Common workflows). The old 465 GB USB HDD (`/mnt/sdc`) was the backup
target until 2026-06-25, when it was physically removed and the SD card took over.
The T7 mounts by UUID; its `sdX` name drifts between boots, so don't address it by
device name.

All guests were created with the [community Proxmox helper scripts](https://community-scripts.github.io/ProxmoxVE/).

Other LAN hosts managed from this repo (not Proxmox guests):

| Host    | Address        | Purpose                                                    |
|---------|----------------|------------------------------------------------------------|
| extrude | `192.168.1.50` | Orange Pi Lite (Armbian, Wi-Fi only) running OctoPrint for the Ender 3 V2 Neo. `http://extrude.home`. See `devices/extrude/README.md` |

## Access

- `ssh homelab` connects to the **Proxmox host as root** (`192.168.1.10`).
- Reach guests from the host: `qm` for the VM, `pct` for LXCs.
  - `pct exec 101 -- <cmd>` runs a command in the AdGuard container.
  - `pct exec 102 -- docker <...>` drives Docker in CT 102.
  - `qm guest exec 100 -- <cmd>` runs in the HAOS VM (qemu-guest-agent is enabled).
- The LXCs also have direct IPs (`.20`, `.30`) if you prefer to SSH them directly,
  but going through the host with `pct exec` needs no extra credentials.
- `ssh root@192.168.1.50` reaches **extrude** (OctoPrint) with the Mac's
  `id_ed25519` key. Passwords are in `devices/extrude/extrude.env`.

## Repo layout

```
proxmox/                 Current Proxmox state (source of truth)
  README.md              Host spec, guest table, rebuild steps
  guests/                Guest config snapshots + app config
    100-haos.conf        qm config snapshot (hand-maintained, carries comments)
    101-adguard.conf     pct config snapshot
    102-docker.conf      pct config snapshot
    adguard/AdGuardHome.yaml   AdGuard config (ENCRYPTED via transcrypt)
    docker/watchtower.compose.yml
    docker/jellystack.compose.yml   migrated *arr/media stack (deployed on CT 102)
    docker/jellystack.env           jellystack secrets (ENCRYPTED via transcrypt)
    docker/jellystack.md            jellystack deploy + storage + tailscale notes
    docker/monitoring.compose.yml   Prometheus/Grafana/exporters (deployed on CT 102)
    docker/monitoring.env           monitoring secrets (ENCRYPTED via transcrypt)
    docker/monitoring.md            observability layout + deploy notes
    docker/books.compose.yml        CWA + Shelfmark ebook pipeline (deployed on CT 102)
    docker/books.env                books secrets (ENCRYPTED via transcrypt)
    docker/books.md                 ebook pipeline + Kobo/KOReader OPDS notes
    docker/selkies-desktop.compose.yml  Selkies/Webtop browser XFCE desktop (deployed on CT 102)
    docker/selkies-desktop.env      selkies-desktop secrets (ENCRYPTED via transcrypt)
    docker/selkies-desktop.md       browser desktop deploy + storage + access notes
    docker/tuliprox/*.yml           tuliprox config (no secrets; ${env:...} from jellystack.env)
    docker/tuliprox.md              live IPTV for Jellyfin: deploy, gotchas, why it left OCI
    docker/valheim.compose.yml      Valheim dedicated server (REMOVED 2026-10-04; world kept on T7)
    docker/valheim.env              valheim server password (ENCRYPTED via transcrypt)
    docker/valheim.md               Valheim deploy, join code, world copy notes
    docker/archive.compose.yml      offline archive: kiwix-serve + file browser (deployed on CT 102)
    docker/archive/zim-list.txt     ZIM files kept by archive-sync.sh
    docker/archive.md               offline archive layout, refresh, offline rebuild notes
    docker/hermes.compose.yml       Hermes: WebUI (in-process agent) + gateway (cron, kanban, Telegram) + mail-mcp + docker-proxy (deployed on CT 102)
    docker/hermes.env               Hermes OpenRouter key, Telegram bot, WebUI password (ENCRYPTED via transcrypt)
    docker/hermes/services-AGENTS.md  rules Hermes follows when it creates services (/opt/hermes/services/AGENTS.md)
    docker/hermes.md                Hermes deploy, config, service creation, security notes
    docker/hermes/gateway/Dockerfile  hermes-gateway image (Python 3.12, agent pinned to match the WebUI)
    docker/hermes/mail/             mail-mcp: the mailbox as MCP tools for Hermes (no send)
    docker/hermes/profiles/*/SOUL.md  instructions for the mail and pa profiles
    docker/mail-triage.env          iCloud IMAP/SMTP creds + Telegram chat, used by mail-mcp (ENCRYPTED via transcrypt)
    docker/mail-mcp.env             mail-mcp bearer tokens (ENCRYPTED via transcrypt)
    docker/vault.compose.yml        SilverBullet wiki + vault-kb MCP + vault-git over /mnt/t7/vault (deployed on CT 102)
    docker/vault.env                SilverBullet login + vault-kb token (ENCRYPTED via transcrypt)
    docker/vault/kb/                vault-kb MCP server source (Dockerfile + server.py)
    docker/vault.md                 vault layout, wiki, KB, git history, email filing
    docker/zomboid.compose.yml      Project Zomboid B42 + Tailscale sidecar; public via OCI relay (deployed on CT 102)
    docker/zomboid.env              PZ admin/server passwords (ENCRYPTED via transcrypt)
    docker/zomboid.md               PZ deploy, OCI relay path, tailnet policy, tailscale login
    docker/homepage.compose.yml     Homepage dashboard, a tile per service (deployed on CT 102)
    docker/homepage.env             Homepage widget API keys/passwords (ENCRYPTED via transcrypt)
    docker/homepage/*.yaml          Homepage config (services, settings, widgets)
    docker/homepage.md              dashboard layout, credentials table, how to add keys/tiles
  host/                  Bare-metal host services (node_exporter, pve-exporter;
                         pve.yml ENCRYPTED via transcrypt)
  scripts/snapshot.sh    Pull live guest/app config back into the repo
  scripts/archive-sync.sh  Monthly refresh of the Kiwix ZIM archive (host cron)
devices/                 Standalone LAN hosts (not Proxmox guests)
  extrude/               OctoPrint on an Orange Pi Lite: README, install script,
                         netplan + credentials (ENCRYPTED via transcrypt)
terraform/               Backblaze B2 backup bucket + key (state encrypted)
ansible/                 Optional: install Docker + deploy stacks onto a host
services/                Deployable docker compose stacks (not all currently running)
  stacks/                base (traefik), autopirate, nextcloud, freshrss, bitwarden, jupyter, backup
  env/                   Per-service env files (ENCRYPTED via transcrypt)
docker-compose-service.yml   SUPERSEDED hotio *arr stack (never deployed; see jellystack)
docker-compose.yml       3musketeers tooling (terraform + ansible containers)
Makefile                 tf-* and ansible-up targets (run tools via docker compose)
```

What is actually running right now: HAOS VM, AdGuard, and on the Docker LXC the
**jellystack** media stack (video + the music pipeline: Lidarr, slskd, Soularr,
Navidrome — see `proxmox/guests/docker/jellystack.md`), `watchtower`, and the
**monitoring** stack
(Prometheus + Grafana + exporters, `proxmox/guests/docker/monitoring.md`), and
the **books** stack (CWA + Shelfmark ebook pipeline for a Kobo,
`proxmox/guests/docker/books.md`), and the **selkies-desktop**
stack (a browser-accessible XFCE desktop streamed over WebRTC,
`proxmox/guests/docker/selkies-desktop.md`), and **tuliprox**, which proxies a
one-connection IPTV subscription into Jellyfin's Live TV
(`proxmox/guests/docker/tuliprox.md`), and the **archive** stack (offline Kiwix
copy of Wikipedia/Stack Exchange/iFixit, `proxmox/guests/docker/archive.md`),
and **Hermes**, a personal AI assistant (hermes-webui at `assistant.home`, the
Hermex iPhone app over Tailscale HTTPS) backed by a cloud model. It can create
and run Docker services on CT 102 on request
(`proxmox/guests/docker/hermes.md`). It also runs Doug's iCloud inbox and a
kanban board of his projects (profiles `mail` and `pa`). It replaced nanobot
and the mail-triage poller on 2026-10-09, and **Homepage**, the dashboard at
`home.home` (`proxmox/guests/docker/homepage.md`), and the **vault** stack: Doug's
knowledge vault (ex-Obsidian, now homelab-only SSOT at `/mnt/t7/vault`), with the
SilverBullet wiki at `vault.home` and the vault-kb MCP server that Hermes
uses (`proxmox/guests/docker/vault.md`), and **Stremio** at `stream.home`, ephemeral torrent streaming inside gluetun's
netns (`proxmox/guests/docker/jellystack.md`), and a **Project Zomboid** server
(`proxmox/guests/docker/zomboid.md`). Players join `play.dkb.nz:16261`, which
the OCI box in `dkbnz/dogs-and-bogs` relays here over Tailscale; this is the
one deliberate internet-facing service, limited by tailnet policy to two UDP
ports on one node. The Valheim server and a local LLM
were removed 2026-10-04 (the LLM starved the host of RAM). The
minecraft servers (both the external survival server and the local creative
prototyping world) are no longer run from this repo; all minecraft moved to the
cloud (2026-06-25). The
Proxmox host itself runs bare-metal node_exporter + pve-exporter (`proxmox/host/`).
Off the Proxmox box, **extrude** (`192.168.1.50`) runs OctoPrint for the 3D printer
(`devices/extrude/README.md`); Caddy on CT 102 serves it as `extrude.home`.
The `services/` stacks are defined but **not deployed**. The root `docker-compose-service.yml` is a superseded
earlier *arr stack, kept for reference only — jellystack
(`proxmox/guests/docker/jellystack.md`) is the real one. Verify with
`pct exec 102 -- docker ps`.

## Secrets (transcrypt)

This is a **public repo**. Secrets are committed encrypted with
[transcrypt](https://github.com/elasticdog/transcrypt) (OpenSSL AES-256-CBC). The
clean/smudge filters encrypt on commit and decrypt in the working tree, so files
look like plaintext locally but are stored as `U2FsdGVk...` blobs.

Patterns that get encrypted live in `.gitattributes`:
```
terraform.tf*    *_key.*    *.key    *.env    AdGuardHome.yaml
```

Rules for agents:
- **Never commit a new secret in plaintext.** Before adding a file with sensitive
  content, make sure a `.gitattributes` pattern matches it, then verify with
  `git show :<path> | head` that the staged blob starts with `U2FsdGVk`.
- To add a new secret type, add a pattern to `.gitattributes` first, then `git add`.
- On a fresh clone, initialise with:
  `transcrypt -c aes-256-cbc -p '<password>'` (recover the password on a configured
  checkout with `./transcrypt --display`).
- Do not print decrypted secret contents into commits, PRs, or chat.

## Common workflows

### Reconcile live state into the repo
After changing anything in the Proxmox UI or on a guest, pull it back:
```shell
proxmox/scripts/snapshot.sh        # writes /tmp/*.cfg for review, updates AdGuardHome.yaml
git add -p && git commit
git push origin main
```
The `*.conf` files are hand-maintained (they carry comments), so the script writes
fresh dumps to `/tmp` for you to diff rather than clobbering them. The snapshot
strips volatile fields (UUIDs, MACs, vmgenid, helper-script HTML descriptions).

### Change a guest's resources
Edit live, then snapshot. Example (give the Docker LXC more RAM):
```shell
ssh homelab 'pct set 102 -memory 12288'
proxmox/scripts/snapshot.sh && git add -p && git commit -m "Bump docker LXC to 12GB"
```
Keep the tracked `.conf` in sync by hand if the snapshot diff shows a real change.

### Deploy / update a Docker stack on CT 102
Compose files are not auto-deployed. To deploy one, copy it into the container and
bring it up:
```shell
ssh homelab 'pct exec 102 -- docker ps'                      # see what's running
# copy a compose file in, then:
ssh homelab 'pct exec 102 -- docker compose -f <file> up -d'
```
`watchtower` updates images daily at 04:00 Pacific/Auckland and prunes old images.

### Backups to the SD card
`proxmox/scripts/sdcard-backup.sh` runs daily at 03:30 (via
`/etc/cron.d/sdcard-backup`) and mirrors the irreplaceable data to
`/mnt/sdcard/backup`. Everything it backs up is now host-visible under `/mnt/t7`
(CT102 `appdata` + `docker` moved to T7 bind mounts 2026-06-25), so it is a single
`rsync` of `/mnt/t7` that keeps `appdata` (*arr DBs + Jellyfin metadata + Tailscale
state), the music library, `monitoring`, `books`, PS4 data, and the offline
`archive` (Kiwix ZIMs + installers, kept because the internet may not be there to
redownload them). It deliberately
skips what is redownloadable or regenerable: the raw video media
(`movies`/`tv`/`downloads`, ~218GB) and `/mnt/t7/docker` (Docker image layers). Run
on demand and check the log:
```shell
ssh homelab '/usr/local/bin/sdcard-backup.sh; tail -5 /var/log/sdcard-backup.log'
```
To restore appdata: stop the stack, then `rsync` `/mnt/sdcard/backup/appdata/` back
over `/mnt/t7/appdata/` on the host (numeric ownership 110000 = container 10000 is
preserved in the backup, so no chown is needed), bring the stack back up.

### Terraform (Backblaze B2)
Terraform manages only the B2 backup bucket + application key. Run through the
3musketeers Make targets (terraform runs in a container, no local install
needed; the pinned `hashicorp/template` provider has no Apple Silicon build):
```shell
make tf-plan
make tf-apply
```
The old GCP headscale control server was decommissioned (2026-06-06); remote
access is Tailscale SaaS (tailnet `shetland-gamma.ts.net`, subnet router on
CT 102 — see `proxmox/guests/docker/jellystack.md`).

## Conventions

- **Live state is the source of truth.** When the repo and the running system
  disagree, snapshot the live state into the repo rather than assuming the repo is
  right. The repo drifted badly once already.
- Guest config `.conf` files mirror `qm config` / `pct config` output but are
  hand-edited to add comments and drop volatile lines. Don't auto-overwrite them.
- Prefer editing live with `qm set` / `pct set` then snapshotting, over editing the
  `.conf` and trying to apply it (Proxmox has no declarative apply for these).
- Commit messages and docs: plain, direct English. No filler.
- Sign agent commits with the trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- Push to `origin main` (`git@github.com:dkbnz/homelab.git`) unless told otherwise.

## Safety

- `ssh homelab` is **root on the hypervisor**. A bad command takes down everything.
  Read before you destroy. Confirm destructive Proxmox actions (`qm destroy`,
  `pct destroy`, `pvesm`, disk/LVM ops, `pct set` that detaches storage) before running.
- Host storage runs hot. `local` (the 25G root fs) hit 100% on 2026-06-13 when it
  held CT 102's mp0/mp2 raw disks; those moved to T7 bind mounts on 2026-06-25,
  dropping `local` to ~19%. A daily `pct fstrim 102` cron reclaims deleted blocks
  on the remaining LVM-thin volumes (see `proxmox/host/README.md`). Check
  `ssh homelab 'pvesm status'` before creating disks, restoring backups, or pulling
  large images.
- Don't expose services to the internet. Remote access is via the Tailscale VPN
  by design — no port forwarding.
  The one exception is Project Zomboid: the OCI box relays two UDP ports to
  the `zomboid` tailnet node, and the tailnet policy confines `tag:pz-relay`
  to exactly those (`proxmox/guests/docker/zomboid.md`). Keep it that narrow.
- The Samsung T7 (ext4, `/mnt/t7`) is the data disk for CT 102 (appdata, docker,
  media, monitoring). Don't reformat or repartition it without an explicit,
  confirmed request. The onboard SD card at `/mnt/sdcard` holds the daily backup of
  the irreplaceable data (appdata DBs, music, PS4 saves); the raw media and the
  Docker layers are deliberately not backed up (redownloadable / regenerable). The
  live data is on the T7 and its only backup is the SD card, so they are the two
  independent copies — losing both at once loses the data.
- Snapshot/back up a guest before risky changes: `ssh homelab 'vzdump <vmid>'`.

## Quick reference

```shell
ssh homelab 'qm list'                       # VMs
ssh homelab 'pct list'                       # LXCs
ssh homelab 'pvesm status'                   # storage usage
ssh homelab 'pct exec 102 -- docker ps'      # docker containers
ssh homelab 'pct exec 101 -- cat /opt/AdGuardHome/AdGuardHome.yaml'
curl -s http://192.168.1.30:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health}'   # scrape health
proxmox/scripts/snapshot.sh                  # reconcile live -> repo
```
