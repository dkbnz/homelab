# books (CT 102)

Ebook pipeline for a Kobo Libra. Request a book, it downloads, gets converted
and filed into a Calibre library, and KOReader on the Kobo pulls it over the LAN
via OPDS. No cable, no cloud, no port forwarding.

**Deployed** on CT 102 (2026-06-10): both containers healthy, `cwa.home` /
`books.home` proxied, the Kobo's KOReader OPDS catalogue pre-seeded. The default
`admin` / `admin123` login has since been changed (verified rejected 2026-06-13);
the current password is in the password manager.

Two containers:

- **CWA** (Calibre-Web-Automated) — the library. Watches an ingest folder,
  converts to EPUB/KEPUB, enriches metadata, dedupes, files into the Calibre
  library, and serves an OPDS catalogue. Web UI + OPDS on `:8083`.
- **Shelfmark** (calibre-web-automated-book-downloader, **lite** image) — the
  request front door. Search a title, pick a result, it downloads (Anna's
  Archive backend) into the shared ingest dir. Web UI on `:8084`. The lite image
  has no bundled browser; it uses the flaresolverr already running in jellystack
  (reached on the host LAN IP `192.168.1.30:8191`) for Cloudflare challenges. The
  full image was tried first but its ~350MB Chromium layer didn't fit on the 12G
  docker disk (mp2 sits ~90% full and `local` is too full to grow it).

The Kobo runs **KOReader** (sideloaded) and reads CWA's OPDS catalogue. The stock
Kobo reader (Nickel) was not used because its native sync needs an HTTPS endpoint
with a trusted cert; OPDS over plain HTTP on the LAN avoids all of that.

## Flow

```
phone/laptop browser  ->  Shelfmark (:8084)  search + request
   -> downloads to /opt/books/data/ingest
   -> CWA watches that dir, converts to KEPUB, files into the library
Kobo on home WiFi  ->  KOReader  ->  OPDS http://192.168.1.30:8083/opds
   -> browse, tap, download to device
```

Request from anywhere (Shelfmark via the Tailscale subnet router on CT 102).
The Kobo only needs to reach the library when it's on home WiFi, so it syncs
when you get home — no Tailscale client on the Kobo required.

## Files

- `books.compose.yml` — the compose file (deploy at `/opt/books/compose.yaml`).
- `books.env` — config/secrets, **encrypted with transcrypt**. Deploy at
  `/opt/books/.env`. Holds PUID/PGID/TZ and the optional Anna's Archive donator
  key. CWA's own login lives in its DB, not here (see the env file's comment).

App data (the `data/` tree) is not tracked here — it lives on CT 102.

## Storage on CT 102

| Path | Backing | Notes |
|------|---------|-------|
| `/opt/books/compose.yaml`, `.env` | rootfs | the deploy files |
| `/opt/books/data` | mp5, bind of host `/mnt/t7/books` (T7, ext4) | CWA config + Calibre library + ingest + Shelfmark config |

`data/` layout:

```
data/
  cwa/config/        CWA settings + app.db (login, OPDS users)
  cwa/library/       the Calibre library (metadata.db + book files)
  ingest/            drop-zone: Shelfmark writes here, CWA ingests from here
  shelfmark/config/  Shelfmark settings + download history
```

PUID/PGID are `10000` like the rest of CT 102. On the T7 (ext4) the files are
owned `110000:110000` on the host, which is uid/gid `10000` inside the
unprivileged container.

The mountpoint is added with (additive bind — does not detach anything):

```shell
ssh homelab 'mkdir -p /mnt/t7/books && pct set 102 -mp5 /mnt/t7/books,mp=/opt/books/data'
```

Update `102-docker.conf` by hand to record the new `mp5` line.

## Backups

No script change needed. `sdc-backup.sh` rsyncs all of `/mnt/t7` minus the
redownloadable raw video media, so `/mnt/t7/books` (library + config) is captured
in the daily 03:30 backup automatically. The Calibre library is the curated,
hard-to-replace part — worth having in the backup set.

## Deploy

```shell
# 1) host: make the T7 dir + bind it into CT 102
ssh homelab 'mkdir -p /mnt/t7/books && pct set 102 -mp5 /mnt/t7/books,mp=/opt/books/data'

# 2) lay down the data tree with the right ownership (10000 inside == 110000 host)
ssh homelab 'pct exec 102 -- mkdir -p /opt/books/data/cwa/config /opt/books/data/cwa/library /opt/books/data/ingest /opt/books/data/shelfmark/config'
ssh homelab 'pct exec 102 -- chown -R 10000:10000 /opt/books/data'

# 3) copy compose + env in (rename to the deploy names)
#    books.compose.yml -> /opt/books/compose.yaml ,  books.env -> /opt/books/.env

# 4) up
ssh homelab 'pct exec 102 -- docker compose -f /opt/books/compose.yaml up -d'
```

CWA needs a Calibre library (`metadata.db`) in `/calibre-library`. Recent CWA
images create an empty one on first start if the dir is empty; if the UI reports
no library, seed one (Calibre desktop -> create an empty library -> copy its
`metadata.db` into `data/cwa/library/`, chown `10000:10000`).

First run:

1. Open `http://192.168.1.30:8083`, log in `admin` / `admin123`, change the
   password (record it in your password manager).
2. In CWA settings, confirm the ingest/library paths and enable OPDS if it
   isn't already on.
3. Open `http://192.168.1.30:8084` (Shelfmark) and run a test search to confirm
   it can reach Anna's Archive; download one book and watch it appear in CWA.

## Kobo side (KOReader + OPDS)

The Kobo already had KOReader (v2022.01), KFMon, and NickelMenu installed. The
OPDS catalogue was pre-seeded by editing KOReader's settings directly while the
device was in USB mass-storage mode (KOReader not running, so no overwrite race):

`/mnt/onboard/.adds/koreader/settings.reader.lua` gained an `opds_servers` entry:

```lua
["opds_servers"] = {
    {
        ["title"] = "Homelab Library (CWA)",
        ["url"] = "http://192.168.1.30:8083/opds",
        ["searchable"] = false,
        ["username"] = "admin",
        ["password"] = "admin123",
    },
},
```

A backup of the pre-edit file is at `settings.reader.lua.bak-before-opds` on the
device. The edit was validated by loading it through a Lua interpreter before
ejecting.

Using the direct IP (not `cwa.home`) on purpose: the Kobo only ever syncs on the
home LAN, and a hardcoded IP removes any dependency on AdGuard DNS + Caddy for a
4-year-old OPDS client. `http://cwa.home/opds` also works from a browser.

To use it: in KOReader open the OPDS catalog (search/magnifier icon ->
OPDS catalog), pick "Homelab Library (CWA)", browse, tap a book, download.

KOReader handles EPUB/PDF/CBZ/MOBI and more, with full typography control.
NickelMenu lets you bounce between KOReader and stock Nickel.

Caveats:
- **The OPDS entry was seeded with CWA's default login `admin` / `admin123`,
  which has since been changed.** The device's `settings.reader.lua` entry (or
  KOReader's edit-catalog UI) must hold the current CWA credentials, or OPDS
  will 401.
- KOReader v2022.01 is old. If OPDS misbehaves, update KOReader (unzip a current
  `koreader-kobo` release into `.adds/koreader`; the settings dir is preserved).
- KOReader is sideloaded, so a Kobo firmware update can occasionally remove it
  (re-run the KFMon install if it disappears).

## Reverse-proxy names (done)

`cwa.home` (CWA) and `books.home` (Shelfmark) are served by the jellystack
Caddy. Caddy can't reach this stack's containers by name (separate compose
network), so the entries proxy the host-published ports — same trick the stack
already uses for grafana/prometheus:

```
http://cwa.home   { reverse_proxy 192.168.1.30:8083 }
http://books.home { reverse_proxy 192.168.1.30:8084 }
```

These live in `caddy/Caddyfile` (deployed at `/opt/jellystack/caddy/Caddyfile`).
The AdGuard wildcard `*.home -> 192.168.1.30` resolves the names; reload Caddy
after editing with
`docker exec caddy caddy reload --config /etc/caddy/Caddyfile`.

The Kobo's OPDS entry still uses the direct IP, not `cwa.home` (see Kobo side).
