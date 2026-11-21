# Offline archive (CT 102)

A local copy of reference material that keeps working without the internet:
Kiwix ZIM files (Wikipedia, Stack Exchange, iFixit, medical), NZ maps, and
installers for the client apps. Set up 2026-10-04.

| URL | What | Direct |
|---|---|---|
| http://wiki.home | kiwix-serve, all ZIMs with one search page | `192.168.1.30:8088` |
| http://files.home | read-only browser over the whole archive dir | `192.168.1.30:8087` |

Both work remotely over the Tailscale subnet router, like the other `.home` names.

## Storage

Host `/mnt/t7/archive` (T7), bound into CT 102 as mp8 `/opt/archive/data`.
Owned by 110000 (container uid 10000).

```
zim/          Kiwix ZIM files (archive-sync.sh)
maps/         NZ OSM extract + Organic Maps / OsmAnd files
installers/   client apps + `docker save` tarballs of this stack's images
```

Size is about 160G: ~155G of ZIMs, under 1G each of maps and installers.
`sdcard-backup.sh` mirrors it to the SD card with the rest of `/mnt/t7`, minus
in-progress `.part` downloads. The ZIMs can be downloaded again today, but the
point of the archive is to outlast the internet, so it is backed up.

## Content and refresh

`proxmox/guests/docker/archive/zim-list.txt` lists what is kept. A copy is
installed on the host at `/usr/local/etc/archive-zim-list.txt`.
`/usr/local/bin/archive-sync.sh` (repo: `proxmox/scripts/archive-sync.sh`) runs
monthly from `/etc/cron.d/archive-sync`, on the 2nd at 00:30. For each entry it
downloads the newest build, checks the published sha256, swaps it in, deletes the
old build, and restarts `kiwix`.

Choices made 2026-10-04:
- Wikipedia `maxi` (119G, with images) over `nopic` (49G). Photos help with
  identifying plants, injuries and parts.
- No Project Gutenberg. The current ZIM is 206G. Pick individual books through
  CWA (books stack) instead.
- No Stack Overflow (107G) or math.SE (6.9G).

A refresh downloads the new build before deleting the old one, so it needs free
space for the whole file plus a 20G margin. If space is short it logs an
`ERROR: skipping` line and leaves the old build in place. With Wikipedia `maxi`
the peak during a refresh is about 290G of the T7's ~324G free (as of 2026-10).
Media growth on the T7 eats into that headroom. Check the log after each monthly run:

```shell
ssh homelab 'tail -20 /var/log/archive-sync.log'
```

Add a ZIM: find it under https://download.kiwix.org/zim/, add `<dir>/<prefix>`
to the list, copy the list to the host, and run the script by hand. An optional
argument filters the list (grep -E):

```shell
scp proxmox/guests/docker/archive/zim-list.txt homelab:/usr/local/etc/archive-zim-list.txt
ssh homelab '/usr/local/bin/archive-sync.sh "physics|chemistry"'
```

Taking a line out of the list does not delete the file. Remove it from
`/mnt/t7/archive/zim` and restart `kiwix`.

The first full sync ran at about 2 MB/s from the Kiwix mirror, so ~155G took
about a day.

## LLM (removed)

A CPU-only local LLM (Ollama + Open WebUI, `granite4.2:8b`) ran here on
2026-10-04 and was removed the same day. With the model loaded it used ~6G RAM;
CT 102 then had ~1G free, host load hit ~70 and the host had 0.8G free.
Measured 4 tokens/s. Open WebUI defaults also overflowed the model's 4096-token
context (built-in tool definitions, ~5900 tokens) and its thinking mode added
minutes per reply. Not worth running on this box. For an assistant see
`hermes.md` (cloud model).

## Offline rebuild

Docker can't pull images without the internet. `installers/images/` holds
`docker save` tarballs of every image in this stack. To restore:

```shell
pct exec 102 -- sh -c 'for f in /opt/archive/data/installers/images/*.tar; do docker load -i "$f"; done'
pct exec 102 -- docker compose -f /opt/archive/compose.yml up -d
```

Re-save after a watchtower update if you want the tarballs current
(`docker save -o <file> <image>`).

## Deploy

```shell
scp proxmox/guests/docker/archive.compose.yml homelab:/tmp/
ssh homelab 'pct push 102 /tmp/archive.compose.yml /opt/archive/compose.yml'
ssh homelab 'pct exec 102 -- docker compose -f /opt/archive/compose.yml up -d'
```

kiwix-serve exits if `zim/` is empty. Fetch at least one small ZIM before the
first `up`.
