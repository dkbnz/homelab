# tuliprox — shared IPTV live TV for Jellyfin

Adds live IPTV to the existing Jellyfin in `jellystack`. No stored media, no DVR.

**Deployed on CT 102 on 2026-09-20.** The provider does not block this host:
a `/live/` pull from CT 102 returned HTTP 200 after a 302 with ~40 MB of MPEG-TS
on three separate channels, so the `proxy:`/gluetun fallback is not in use.

This was first built on the `dkbnz/dogs-and-bogs` OCI box and **abandoned there**
because that provider blocks datacenter IPs for video (see
[Why this moved here](#why-this-moved-here)). Everything below is already
debugged; the notes exist so this does not have to be rediscovered.

```
provider (Xtream Codes) -> tuliprox -> Jellyfin -> Caddy (jellyfin.home) -> viewers
                           1 upstream  existing    existing
                           conn, fanned server
                           out to N
```

## The constraint that shapes everything

**The provider allows ONE concurrent connection** (`max_connections: 1`,
confirmed via its own API). tuliprox pulls a channel once and multicasts it
locally (`share_live_streams: true`), so any number of viewers on the **same**
channel costs one provider slot. Two **different** channels at once needs two
slots and the provider refuses the second. That is a provider limit; nothing in
this stack works around it.

Provider account as of 2026-09-20:

```
auth 1 | status Active | is_trial 0 | active_cons 0 | max_connections 1
exp_date 1792437515  ->  2026-10-19 19:18 UTC
```

Query it any time:

```shell
source /opt/jellystack/.env
curl -s "${XTREAM_URL}/player_api.php?username=${XTREAM_USERNAME}&password=${XTREAM_PASSWORD}&action=get_account_info" | jq .user_info
```

## What to deploy

### 1. Config files

`proxmox/guests/docker/tuliprox/{config.yml,source.yml,api-proxy.yml}` in this
repo, deployed to `/opt/jellystack/tuliprox/config/` on CT 102. They contain no
secrets — they interpolate `${env:...}` from `/opt/jellystack/.env`.
`audit-filter.py` in the same directory is a host-side tool and is not deployed.

```shell
ssh homelab 'pct exec 102 -- mkdir -p /opt/jellystack/tuliprox/{config,data,backup}'
# then rsync/scp the three yml files into /opt/jellystack/tuliprox/config/
```

### 2. Secrets in `jellystack.env`

Append to `proxmox/guests/docker/jellystack.env` (transcrypt-encrypted by the
`*.env` rule in `.gitattributes`, so it is safe in this public repo):

```ini
# --- IPTV provider (Xtream Codes) ---
# URL is scheme+host+port only: no /player_api.php, no trailing slash.
XTREAM_URL=
XTREAM_USERNAME=
XTREAM_PASSWORD=
# openssl rand -hex 16 — must stay stable or in-flight HLS sessions break
TULIPROX_PROXY_REWRITE_SECRET=
# password Jellyfin uses to authenticate to tuliprox; never leaves the host
TULIPROX_JELLYFIN_PASSWORD=
```

**Ask Doug for the three `XTREAM_*` values** — they came from his IPTV provider
account. The OCI copy at `/opt/minecraft/tuliprox.env` was **deleted** on
2026-09-20 when that build was reverted, so there is no second copy to recover.
Generate the other two yourself:

```shell
openssl rand -hex 16                  # TULIPROX_PROXY_REWRITE_SECRET
openssl rand -base64 24 | tr -d /+=   # TULIPROX_JELLYFIN_PASSWORD
```

### 3. Service block for `jellystack.compose.yml`

```yaml
  # Live IPTV proxy for Jellyfin. The provider allows ONE concurrent connection,
  # so tuliprox pulls each channel once and multicasts it to every viewer.
  # No ports: Jellyfin reaches it on the compose network. Add a Caddy vhost only
  # if you enable the web UI (off by default in config.yml).
  tuliprox:
    image: ghcr.io/euzu/tuliprox:latest   # = 3.3.0; do NOT use :dev, see below
    container_name: tuliprox
    environment:
      - TULIPROX_HOME=/app               # config.yml interpolates this
      - TZ=${TZ}
      - XTREAM_URL=${XTREAM_URL}
      - XTREAM_USERNAME=${XTREAM_USERNAME}
      - XTREAM_PASSWORD=${XTREAM_PASSWORD}
      - TULIPROX_PROXY_REWRITE_SECRET=${TULIPROX_PROXY_REWRITE_SECRET}
      - TULIPROX_JELLYFIN_PASSWORD=${TULIPROX_JELLYFIN_PASSWORD}
    volumes:
      - ./tuliprox/config:/app/config
      - ./tuliprox/data:/app/data
      - ./tuliprox/backup:/app/backup
    healthcheck:
      test: ["CMD", "/app/tuliprox", "--healthcheck"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: unless-stopped
```

`PUID`/`PGID` do nothing here — the image is distroless and runs as root, so
`./tuliprox/*` ends up root-owned, unlike the rest of the stack.

Deploy as usual:

```shell
ssh homelab 'pct exec 102 -- docker compose -f /opt/jellystack/compose.yaml up -d tuliprox'
```

### 4. Wire it into Jellyfin

**Use the M3U tuner, not HDHomeRun.** Dashboard → Live TV → Tuner Devices → `+`
→ M3U Tuner:

```
http://tuliprox:8901/get.php?username=jellyfin&password=<TULIPROX_JELLYFIN_PASSWORD>&type=m3u_plus&output=ts
```

Then TV Guide Data Providers → `+` → XMLTV:

```
http://tuliprox:8901/xmltv.php?username=jellyfin&password=<TULIPROX_JELLYFIN_PASSWORD>
```

Both come from tuliprox, so the channel IDs already line up and no manual
channel mapping is needed. Finally run the **Refresh Guide** scheduled task.

Jellyfin already had a Live TV setup before this: an M3U tuner on
`https://i.mjh.nz/nz/raw.m3u8` (free NZ FTA) plus its XMLTV guide. tuliprox was
added **alongside** it, not over it. Both listing providers are left on "all
tuners", which is the UI default; they match by channel id, so the mjh guide
does not attach itself to tuliprox channels. As deployed:

| | id |
|---|---|
| tuliprox M3U tuner | `d6eebea2ab3b4422886efa33770f6ad9` |
| tuliprox XMLTV provider | `591b8fc716f6413185f7eef13ecf509c` |
| mjh.nz M3U tuner (pre-existing) | `5e65961d96bf46c19df47a4ba2da4b6e` |
| mjh.nz XMLTV provider (pre-existing) | `a16dfa4566d2491e8843f7f96fb00512` |

`livetv.xml.bak-20260920` in `appdata/jellyfin/` is the config from before the
tuliprox tuner was added.

Via the API instead (note the auth header — see gotchas):

```shell
K=<api-key>; H="Authorization: MediaBrowser Token=\"$K\""; J=http://jellyfin:8096
curl -s -H "$H" -H "Content-Type: application/json" -X POST $J/LiveTv/TunerHosts \
  -d '{"Type":"m3u","Url":"<m3u url>","FriendlyName":"Dogs and Bogs TV","TunerCount":4,
       "ImportFavoritesOnly":false,"AllowHWTranscoding":true,"EnableStreamLooping":false}'
curl -s -H "$H" -H "Content-Type: application/json" -X POST \
  "$J/LiveTv/ListingProviders?validateListings=false" \
  -d '{"Type":"xmltv","Path":"<xmltv url>","EnableAllTuners":true,
       "NewsCategories":[],"SportsCategories":[],"KidsCategories":[],"MovieCategories":[],
       "EnableNewProgramNotifications":false}'
```

Measured result on 2026-09-20: **16,449 channels**, not the 5,500-6,500 this
file used to predict. That old figure was extrapolated from title-prefix counts
and undercounted badly, because the filter also matches on category and whole
`US|`/`UK|` categories are far larger than their `US:`/`UK:` titled members.
See [Channel filter](#channel-filter) and
[What 16,449 channels costs](#what-16449-channels-costs).

## Differences from the OCI build

| | OCI (abandoned) | here |
|---|---|---|
| Hardware encode | none (virtio-gpu) | **QuickSync**, UHD 620 via `/dev/dri` |
| Transcoding policy | forced off per user | can stay **on** |
| `not_hevc` filter | required | **removed** — QSV handles HEVC |
| Provider IP block | **blocked (456)** | residential IP works |
| Jellyfin | new install | existing, `jellyfin.home` |
| Egress budget | 10 TB/mo OCI cap | not a concern |
| Public exposure | Caddy + Let's Encrypt | LAN + Tailscale only |

On OCI every user had *"Allow media playback that requires transcoding"* turned
**off**, because a software x264 transcode would have starved the Minecraft
server sharing the box. **You do not need that here** — QSV handles it. Two
things still worth knowing:

- Live TV is remux-first, but **`/Items/{id}/PlaybackInfo` does not show that**.
  It returns `SupportsDirectStream: false, SupportsDirectPlay: false` and a
  `TranscodingUrl` for every M3U Live TV channel, including the pre-existing
  mjh.nz ones, whatever device profile you send — a wide-open profile changes
  nothing. Do not read that as a fault. The real decision is made when the
  stream opens: the master playlist comes back with `AudioCodec=copy` and
  ffmpeg runs `-codec:v:0 copy ... -codec:a:0 copy`, and Jellyfin names the log
  `FFmpeg.Remux-<date>_<mediasource>.log`. Check the log filename, not
  PlaybackInfo. `UK: SKY SPORT NEWS` remuxed h264 1080p50 + eac3 on 2026-09-20.
  Transcoding only kicks in for a codec the client cannot handle — a browser
  will re-encode the eac3 audio on these channels while still copying video.
- A UHD 620 realistically does 2-3 concurrent 1080p transcodes. With a
  1-connection provider that ceiling is unlikely to bite in practice.

## Channel filter

Wanted markets: **NZ, AU, US, UK, CA**. The filter in `source.yml` matches on
**both** the category and the channel title, because the provider prefixes
categories with a pipe (`UK| GENERAL ᴴᴰ/ᴿᴬᵂ`) and titles with a colon
(`UK: SKY SPORT NEWS ᴿᴬᵂ`). Matching titles alone misses whole categories.

`not_hevc` has been **removed**. It only existed because the OCI box had no
encoder; QuickSync makes those ~850 channels usable.

Measured on 2026-09-20. The provider carries 56,555 **live** channels in 917
categories (the 287,382 / 1,742 figures tuliprox logs as `raw` count VOD and
series too). The auditor's verdict on the deployed filter:

```
KEEP        14826  (26.2%)
drop        36445
separators   5284
```

kept by market, counted by category prefix:

| market | channels |
|---|---|
| US | 9,972 |
| UK | 2,963 |
| CA | 1,407 |
| AU | 355 |
| NZ | 72 |
| matched on title only | 57 |

tuliprox's own target count is **16,449**, higher than the auditor's 14,826
because the auditor only reads `get_live_streams` while the target also picks up
market-matching VOD/series entries.

### What 16,449 channels costs

Most of that is not live television. **10,866 of the 14,826 kept channels sit in
VOD- or PPV-style categories** — `US| FLO ⱽᴵᴾ PPV` (1,000), `US| PRIME ᴿᴬᵂ`
(673), `US| ROKU ᴿᴬᵂ` (652), `US| ESPN+ PPV` (600), `US| 24/7 COMEDY` (426) and
so on. The `24/7:` entries are looped box sets (`24/7: DERRY GIRLS`,
`24/7: TOM AND JERRY TALES`); the `PPV` entries are largely scheduled-event
placeholders carrying a date in the title, dead outside their window. Strip
those and the genuine live-TV remainder is about **3,960 channels**.

The cost lands on Jellyfin's **Refresh Guide** task, which re-downloads and
re-parses the entire 1.1 MB XMLTV file **once per channel**:

```
[INF] Jellyfin.LiveTv.Listings.XmlTvListingsProvider: xmltv path: "http://tuliprox:8901/xmltv.php?..."
```

That line repeats 16,449 times. It runs at roughly 1% per minute with one core
pegged, so a full guide refresh takes about **90 minutes**, and the trigger is a
24-hour interval. At ~4,000 channels it would be about 20 minutes.

To cut the VOD/PPV bulk, add a term to `channel_lineup` in `source.yml`:

```yaml
  - name: not_vod
    value: 'NOT (Group ~ ".*(24/7|PPV|ON AIR|NETFLIX|PRIME|ROKU|TUBI|PEACOCK|PARAMOUNT\+|MAX |STAN|CINEMA TV SHOWS).*")'
  - name: channel_lineup
    value: "!wanted_markets! AND !not_separator! AND !not_vod!"
```

Re-run `audit-filter.py` afterwards, then Refresh Guide.

### Spanish and French in the US/CA markets

Counted by name match on 2026-09-20, so treat these as a floor, not a census:

| | kept | Spanish-language | French-language |
|---|---|---|---|
| US | 9,977 | ~194 | ~6 |
| CA | 1,408 | ~1 | ~86 |

US Spanish is concentrated in `US| TELEMUNDO NETWORK` (59), `US| ROKU` (58) and
`US| PRIME` (15) — Telemundo, Univision, HBO Latino, Max Latino. US French is
noise: four Ligue-1-style PPV events and one mislabelled title.

CA French is a real block and cleanly separated: `CA| GENERAL FR` (31),
`CA| KIDS FR` (8), `CA| CINEMA FR` (7), `CA| SPORTS FR` (7),
`CA| DOCUMENTARY FR` (7), `CA| MUSIC FR` (2), plus ~21 mixed into
`CA| CANADA ᴴᴰ/ᴿᴬᵂ` (RDS, TVA, LCN, ICI). ~300 channels total, under 2% of the
lineup. To drop them:

```yaml
  - name: not_french_ca
    value: 'NOT (Group ~ "^\s*CA\s*\|.*\bFR\b.*")'
```

### Check what the filter excludes

Before assuming anything is missing, run the auditor. It is read-only, hits only
`player_api.php`, and does **not** open a stream, so it will not consume the
provider's single connection slot:

```shell
source /opt/jellystack/.env
python3 proxmox/guests/docker/tuliprox/audit-filter.py
python3 .../audit-filter.py --markets NZ,AU,US,UK,CA,IE   # try a wider net
python3 .../audit-filter.py --show-kept                   # full kept list
```

It prints a KEEP/DROP verdict per category, a per-market tally, and a
**"DROPPED but possibly English"** list flagging categories whose names contain
things like `4K`, `UHD`, `VIP`, `GOLD`, `SPORT`, `IE` — the buckets most likely
to hide English channels behind a non-country prefix. Widen `--markets` or add an
`OR` term to `channel_lineup` until that list is empty of things you want.

### The 4K/8K categories — resolved, leave `also_uhd` off

Audited on 2026-09-20. Four categories carry a `4K|`/`8K|` prefix:

| category | channels | what is in it |
|---|---|---|
| `8K| SPORT ON AIR ⁸ᴷ` | 580 | FR 124, IT 56, PL 53, DE 45, GR 35, HR 31 … UK 19, NZ 12 |
| `4K| 24/7 ᵁᴴᴰ ³⁸⁴⁰ᴾ` | 45 | all Arabic (`AR 4K:` drama, Arabic-script titles) |
| `4K| ᵁᴴᴰ ³⁸⁴⁰ᴾ` | 44 | mixed: Sky Sports F1/Darts, TNT Sports, ESPN, Sportsnet 360 next to V SPORT, ELEVEN ᴾᴸ, IRIB, TF1, nine Sky Primafila |
| `4K| RELAX ᵁᴴᴰ ³⁸⁴⁰ᴾ ☼` | 26 | ambient loops (ocean, forest), no language |

Enabling `also_uhd` adds ~695 channels of which the clear majority are not
English, so leave it off.

The useful part is already coming through without it. `wanted_markets` matches
on title as well as category, so the `UK:` and `NZ:` titled channels inside
`8K| SPORT ON AIR ⁸ᴷ` are **already kept** — that is most of the 57 "matched on
title only" rows. `UK: SKY SPORT NEWS ᴿᴬᵂ`, the channel used to verify playback
end to end, lives in that category and arrives with `tvg-chno="1"`.

What `also_uhd` would genuinely add is the dozen or so `4K:`-prefixed UK sports
channels in `4K| ᵁᴴᴰ ³⁸⁴⁰ᴾ` (Sky Sports F1, Sky Sports Darts, TNT Sports). If
those are wanted, target them directly rather than pulling in all four
categories:

```yaml
  - name: also_uhd_english
    value: 'Title ~ "^\s*4K:\s*(SKY SPORT|TNT|NOW SPORTS|ESPN|SPORTSNET|BLOOMBERG|LOVE NATURE|MUSEUM).*"'
```

## Gotchas (all of these cost time on the first build)

**tuliprox image lags its own documentation.** `:latest` is **3.3.0** (Apr 2026).
The git tags run to v3.3.114 but no images are published for them, and the docs
on `develop` describe a newer schema. Two rejections on 3.3.0:
- `share_live_streams` is a plain **bool**. The nested `{hls, mpeg_ts}` form
  fails with `unexpected event: expected string scalar`.
- every target **must** have a `filter`, even `'Title ~ ".*"'`.
Read the docs at the `v3.3.0` tag.

**Never run `:dev`.** 3.3.114 does not fix the JSON bug below, and it *rewrites*
`api-proxy.yml` on startup, expanding `${env:TULIPROX_JELLYFIN_PASSWORD}` into
plaintext in a repo-tracked file. If it ever runs, restore `api-proxy.yml` from
git and check nothing leaked.

**`lineup.json` is not valid JSON, so the HDHomeRun tuner is unusable.** Both
3.3.0 and 3.3.114 emit a trailing comma — `[{...},]`, and `[,]` when empty.
Jellyfin throws:

```
Jellyfin.LiveTv.TunerHosts.HdHomerun.HdHomerunHost.GetLineup(...)
  -> System.Text.Json ... JsonReaderException
TotalRecordCount: 0
```

Hence the M3U tuner. `hdhomerun.enabled: false` in `config.yml` documents this.

**EPG needs an explicit `epg.sources` block on the input.** Without it XMLTV
returns HTTP 200 with a ~137-byte empty guide. `url: "auto"` derives the
provider's own `xmltv.php`; output goes to ~580 KB.

**`docker restart tuliprox` does not pick up `.env` changes.** Environment is
fixed at container creation. Use
`docker compose -f /opt/jellystack/compose.yaml up -d --force-recreate tuliprox`.
This one wasted a cycle: the env file was correct, the container was still
running the old placeholder values.

**Debug logging leaks credentials.** At `log_level: debug` the `request_url=`
diagnostics line prints the full provider URL with username and password,
despite `sanitize_sensitive_info: true` redacting the other occurrences. Set it
back to `info`.

**Jellyfin 12.1 changed API auth.** `X-Emby-Token` and `?api_key=` both return
401. Only `Authorization: MediaBrowser Token="<key>"` works. (The linuxserver
image here may still be on 10.x, where the old headers work — check
`/System/Info/Public`.)

**Do not `pkill -f jellyfin-ffmpeg/ffmpeg`.** The Jellyfin server's own command
line is `/usr/bin/jellyfin --ffmpeg=/usr/lib/jellyfin-ffmpeg/ffmpeg`, so that
pattern matches the server, kills it, and aborts whatever scheduled task was
running. It cost a 17-minute guide refresh on 2026-09-20. Match on
`/usr/lib/jellyfin-ffmpeg/ffmpeg -` (note the trailing argument dash) or kill
the pid.

**Closing a live stream started over the API does not release the slot.**
`POST /LiveStreams/Close` and `DELETE /Videos/ActiveEncodings` both return 204
and both leave the ffmpeg running, because an API-key request has no session for
Jellyfin to tear down. tuliprox keeps reporting `Active Users: 1` and the
provider's single connection stays occupied. Kill the ffmpeg pid, then confirm
`Active Users: 0` in `docker logs tuliprox`.

**tuliprox is distroless.** No shell, so `docker exec tuliprox sh` fails. Run the
binary directly: `docker run --rm ghcr.io/euzu/tuliprox:latest /app/tuliprox --help`.
It has a `--healthcheck` flag, wired into the compose block above.

**A real stream and the failure clip look identical.** When tuliprox cannot reach
the provider it returns **HTTP 503 with a ~3-4 MB 1080p H.264/AAC clip** reading
"This Channel is Currently Unavailable". It starts with the same `0x47` MPEG-TS
sync byte as a real stream, so byte counts and sync-byte checks prove nothing.
**Always check the status code.**

## Why this moved here

On OCI every channel returned that fallback. The upstream error was **HTTP 456**
from the provider's streaming edge:

```
Provider request failed: Request failed (456):
  http://cf.business-cloud-8.ru/live/<user>/<pass>/1968684.ts
```

Proven to be IP-based, not configuration:

| request source | result |
|---|---|
| residential IP, VLC UA | 302 -> edge host -> **HTTP 200, 34.8 MB of MPEG-TS** |
| OCI `159.13.57.100`, same URL and UA | **456, 0 bytes** |

- Not the User-Agent: `curl`, `Jellyfin/12.1`, `VLC`, `Lavf` and a browser string
  all returned 456 from OCI. Note tuliprox forwards the **client's** UA upstream,
  so `default_user_agent` never applies to stream requests.
- Not the connection limit: `active_cons 0, max_connections 1, status Active`.
- `player_api.php` was **not** blocked, which is why the playlist and EPG loaded
  and everything looked healthy until playback.

The provider blocks datacenter ranges to stop restreaming. A residential
connection is expected to work — the 200 above came from a machine on a home
connection, though not verified from CT 102 itself, so **test this first**:

```shell
# from CT 102, before deploying anything
ssh homelab 'pct exec 102 -- curl -s -o /dev/null -w "%{http_code}\n" -L \
  -A "VLC/3.0.20 LibVLC/3.0.20" "<any /live/ URL from the m3u>"'
```

`200` (after a 302) means good. `456` means this host is blocked too, and the
fallback is `config.yml`'s `proxy:` block, which forces **every** outgoing
request — playlist, EPG and video — through a SOCKS5/HTTP proxy:

**Run on 2026-09-20 from CT 102, three UK channels:** `200` after one redirect,
31-40 MB each. Not blocked. The `proxy:` block stays unused.

```yaml
proxy:
  url: socks5://gluetun:1080
  username: "..."
  password: "..."
```

`gluetun` is already in this stack. Only **one** stream crosses that tunnel no
matter how many people watch, because the fan-out happens locally.

## Verifying it

```shell
NET=jellystack_default
PW=<TULIPROX_JELLYFIN_PASSWORD>
# playlist loaded? compare against what audit-filter.py predicted
docker run --rm --network $NET curlimages/curl -s \
  "http://tuliprox:8901/get.php?username=jellyfin&password=$PW&type=m3u_plus&output=ts" | grep -c EXTINF
# EPG? expect ~580 KB, not 137 bytes
docker run --rm --network $NET curlimages/curl -s -o /dev/null -w "%{size_download}\n" \
  "http://tuliprox:8901/xmltv.php?username=jellyfin&password=$PW"
# a real stream? 200 = working, 503 = provider refused (see above)
docker run --rm --network $NET curlimages/curl -s -o /dev/null -w "%{http_code}\n" --max-time 8 \
  "http://tuliprox:8901/m3u-stream/jellyfin/$PW/20.ts"
docker logs --tail 30 tuliprox
```

Measured on 2026-09-20: **16,449** `EXTINF` lines (5.6 MB m3u), XMLTV
**1,110,316 bytes**, stream status **200** with 30-40 MB pulled in 15 s.

A healthy update logs:

```
stats: [{"inputs":[{"name":"provider","type":"xtream","errors":0,
  "raw":{"groups":1742,"channels":287382},
  "processed":{"groups":221,"channels":16449},"took":"1:31 mins"}],
  "targets":[{"target":"live","success":true}]}]
```

The `HdHomeRun device 'hdhr1' has no username and will be disabled` warning at
startup is expected — `hdhomerun.enabled` is false on purpose.

Concurrent viewers show as `Active Users: 1, Active User Connections: 2` — one
account, two viewers, still one provider slot.

## Legal note

Redistributing a subscription IPTV stream to other people generally breaches the
provider's terms. The 456 block exists precisely to prevent it. Running it on
home infrastructure moves that risk onto the home connection.
