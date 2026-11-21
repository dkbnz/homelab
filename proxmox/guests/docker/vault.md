# Vault (CT 102)

Doug's knowledge vault: the former Obsidian vault (PARA layout), moved off iCloud
on 2026-10-05. The homelab copy is the single source of truth. There is no sync
to the Mac or phone. You browse and edit it in SilverBullet, Hermes reads and
edits it through vault-kb, and Hermes's `mail` profile files facts from email into it.

The old iCloud copy (`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/dkb.nz`,
symlinked from `~/vault` on the Mac) is stale from 2026-10-05. Don't edit it.

## Layout

Host `/mnt/t7/vault`, bound into CT 102 as mp10 `/opt/vault`. About 19GB, mostly
images and PDFs. Files are owned by host uid 101000 (uid 1000 in CT 102's
containers). `sdcard-backup.sh` mirrors it to the SD card with the rest of the T7.

Stack files in CT 102 at `/opt/vault-stack/` (rootfs): `compose.yml`
(`vault.compose.yml`), `vault.env`, `kb/` (image source), `index/` (vault-kb
SQLite index, rebuildable), `models/` (embedding model cache).

| Service | What | Address |
|---------|------|---------|
| silverbullet | Wiki over the vault | http://vault.home (direct :3030) |
| vault-kb | MCP knowledge-base server | http://172.31.77.2:8770/mcp on `kbnet` only |
| vault-git | Auto-commits text files every 10 min | none |

## SilverBullet

- Login: `SB_USER` in `vault.env` (`grep SB_USER proxmox/guests/docker/vault.env`).
- iPhone: open http://vault.home in Safari, Share -> Add to Home Screen.
- The service worker is off (`SB_DISABLE_SERVICE_WORKER`). By default the
  client copies the whole space into the browser for offline use, which would
  mean 19GB of attachments. So it only works online (LAN or Tailscale).
- Image is `latest-slim` with `SB_FS_WATCH=poll` (60s) and `*.tgz`/`*.zip`
  hidden. The full image's server-side Chromium plus the default watcher kept
  re-reading the whole 19GB (about 300MB/s, 2-3 CPUs, host load 9). With these
  settings it idles at about 35MB and 0% CPU.
- Pages are edited in place: typing on a page saves straight to the file. A
  stray keystroke is a real edit, and git history is how to undo it.
- SilverBullet may create its own pages (e.g. `CONFIG.md`, `Library/`) in the
  vault root. That's expected.
- Obsidian-only syntax (Dataview, latex-suite) shows as plain text. Only 7
  notes used `[[wiki links]]` at migration, so link resolution differences
  don't matter much.

## Git history (vault-git)

`/mnt/t7/vault/.git`. Every 10 minutes it commits text files only: `.md`,
`.txt`, `.csv`, `.canvas`. Binaries are excluded by the whitelist in
`.git/info/exclude`, so the repo stays small. Use it to review and roll back
edits by anyone, including Hermes and email:

```shell
ssh homelab 'pct exec 102 -- docker exec vault-git git -C /vault log --stat -5'
ssh homelab 'pct exec 102 -- docker exec vault-git git -C /vault log -p -- "2. Areas/Property/Notes.md"'
ssh homelab 'pct exec 102 -- docker exec vault-git git -C /vault checkout <sha> -- "<path>"'   # restore a note
```

## vault-kb (MCP for Hermes)

`vault/kb/server.py`, built locally as `vault-kb:1` (Watchtower skips it).

- Index: SQLite with FTS5 (keywords) plus `BAAI/bge-small-en-v1.5` embeddings
  (local fastembed, CPU), merged with reciprocal rank fusion. Covers `.md`/`.txt`
  and the text layer of PDFs (no OCR; scanned PDFs have no text). Rescans every
  2 minutes, and re-indexes a note immediately when it writes one.
- Excluded from everything (read, list, search, write): `4. Archives` and
  `2. Areas/Identity` (`KB_EXCLUDE`), plus dot folders. Excluded content never
  goes to the cloud model. Hermes can't read the vault around this through
  its file tools, but it has Docker access to CT 102 (see `hermes.md`,
  Security), so the exclusion is not a hard boundary for it.
- MCP tools: `search`, `read`, `list`, `backlinks`, `recent_changes`, `history`,
  `write`, `edit`, `append`, `move`. Hermes can edit any non-excluded note.
  Git history is the safety net.
- REST (was for the retired mail-triage poller, now unused): `POST /api/search {query, limit}`,
  `POST /api/append {path, text, heading}`. All routes except `/health`
  need `Authorization: Bearer $KB_TOKEN`.
- Network: `kbnet` (172.31.77.0/29, external, created once with
  `docker network create --subnet 172.31.77.0/29 kbnet`). vault-kb has fixed
  IP .2. `hermes` and `hermes-gateway` join kbnet.
- `KB_TOKEN` is in both `vault.env` (server) and `hermes.env` (Hermes MCP
  header; also in Hermes's `data/.env`, see `hermes.md`). Keep them the same.
- Drop folder: `0. Inbox/Drop/`. Put PDFs and notes there, and ask Hermes to
  file them. It reads them and uses `move` to put them in the right PARA folder.

## Email -> vault

Hermes's `mail` profile (see `hermes.md`, Mail) searches vault-kb for each
email's sender and subject for context. When an email carries a lasting fact it
appends `- <date>: <fact> (email from X: subject)` under `## From email` in a
note the search returned. Its instructions say not to create notes or write
anywhere else, but unlike the old poller this is the model's choice, not code.

Text under `## From email` came from untrusted email. vault-kb's MCP instructions
tell Hermes to treat it as data, but it is still attacker-influenced text that
the agent reads. Review it in git history if something looks off.

## Deploy

```shell
# once
ssh homelab 'pct set 102 -mp10 /mnt/t7/vault,mp=/opt/vault'
ssh homelab 'pct exec 102 -- docker network create --subnet 172.31.77.0/29 kbnet'
# copy vault.compose.yml -> /opt/vault-stack/compose.yml, vault.env -> /opt/vault-stack/vault.env,
# vault/kb/* -> /opt/vault-stack/kb/, then:
ssh homelab 'pct exec 102 -- docker compose -f /opt/vault-stack/compose.yml up -d --build'
```
