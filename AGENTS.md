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

Hardware: Intel i7-8650U, 16 GB RAM. `sda` 64 GB SanDisk SSD (boot, `local`,
`local-lvm`); `sdb` 931 GB Samsung T7 (**ext4**, data; bound into CT 102 as mp1
`jellystack-media` + mp3 `minecraft`); `sdc` 465 GB USB HDD (ext4,
mounted `/mnt/sdc`; holds the daily `sdc-backup.sh` backup of appdata + minecraft +
PS4 data - see Common workflows).

All guests were created with the [community Proxmox helper scripts](https://community-scripts.github.io/ProxmoxVE/).

## Access

- `ssh homelab` connects to the **Proxmox host as root** (`192.168.1.10`).
- Reach guests from the host: `qm` for the VM, `pct` for LXCs.
  - `pct exec 101 -- <cmd>` runs a command in the AdGuard container.
  - `pct exec 102 -- docker <...>` drives Docker in CT 102.
  - `qm guest exec 100 -- <cmd>` runs in the HAOS VM (qemu-guest-agent is enabled).
- The LXCs also have direct IPs (`.20`, `.30`) if you prefer to SSH them directly,
  but going through the host with `pct exec` needs no extra credentials.

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
  host/                  Bare-metal host services (node_exporter, pve-exporter;
                         pve.yml ENCRYPTED via transcrypt)
  scripts/snapshot.sh    Pull live guest/app config back into the repo
terraform/               GCP headscale control server (separate concern; state encrypted)
  headscale/             Headscale module + cloud-init templates
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
Navidrome — see `proxmox/guests/docker/jellystack.md`), a **minecraft**
Paper server with its Tailscale sidecar + Discord bot (see
`proxmox/guests/docker/minecraft.md`), `watchtower`, and the **monitoring** stack
(Prometheus + Grafana + exporters, `proxmox/guests/docker/monitoring.md`). The
Proxmox host itself runs bare-metal node_exporter + pve-exporter (`proxmox/host/`).
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

### Backups to sdc
`proxmox/scripts/sdc-backup.sh` runs daily at 03:30 (via `/etc/cron.d/sdc-backup`)
and mirrors the irreplaceable data to `/mnt/sdc/backup`: CT102 `appdata` (*arr DBs +
Jellyfin metadata + Tailscale state) and the T7's minecraft world, music, and PS4
data. It deliberately skips the raw video media (`movies`/`tv`/`downloads`, ~218GB)
since that is redownloadable. Run on demand and check the log:
```shell
ssh homelab '/usr/local/bin/sdc-backup.sh; tail -5 /var/log/sdc-backup.log'
```
To restore appdata: stop the stack, replace `/opt/jellystack/appdata` from
`/mnt/sdc/backup/ct102-appdata`, fix ownership (`chown -R 10000:10000`, TS state dirs
`0:0`), bring the stack back up.

### Headscale (GCP) via terraform
Run through the 3musketeers Make targets (terraform runs in a container, no local
install needed):
```shell
make tf-plan
make tf-apply
```
This infra lives in GCP and is **not visible from the Proxmox host** — verify it
through terraform/GCP, not by inspecting the lab.

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
- `local-lvm` runs hot (was ~95% full). Check `ssh homelab 'pvesm status'` before
  creating disks, restoring backups, or pulling large images.
- Don't expose services to the internet. Remote access is via the headscale/tailscale
  VPN by design — no port forwarding.
- The Samsung T7 (`sdb`, now ext4) is the data disk for CT 102 (media + minecraft
  world). Don't reformat or repartition it without an explicit, confirmed request.
  `sdc` holds the daily backup of the irreplaceable data (appdata DBs, minecraft
  world, PS4 saves); the raw media is deliberately not backed up (redownloadable).
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
