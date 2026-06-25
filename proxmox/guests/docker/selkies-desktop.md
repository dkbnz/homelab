# selkies-desktop — browser Linux desktop on CT 102

A browser-accessible XFCE desktop streamed over WebRTC. Uses
`lscr.io/linuxserver/webtop:debian-xfce`, which is built on the
[Selkies](https://github.com/selkies-project/selkies) stack (KasmVNC/Selkies
baseimage). Deployed as its own compose project on the Docker LXC (CT 102),
reached like the books/monitoring stacks: a host-published port plus a Caddy
`*.home` route.

## Files

| File | Purpose |
|------|---------|
| `selkies-desktop.compose.yml` | the `webtop` service |
| `selkies-desktop.env` | `CUSTOM_USER` / `PASSWORD` (ENCRYPTED via transcrypt) |
| `caddy/Caddyfile` | adds `http://desktop.home -> 192.168.1.30:3010` |

## Access

- **LAN:** `http://192.168.1.30:3010` (http) or `https://192.168.1.30:3011`
  (self-signed).
- **`http://desktop.home`:** via Caddy on CT 102. Resolves through AdGuard's
  `*.home -> 192.168.1.30` wildcard; works on the LAN and from any tailnet device
  via the subnet router (see `jellystack.md`). No new AdGuard entry needed.
- Login uses `CUSTOM_USER` / `PASSWORD` from `selkies-desktop.env`. Without them
  the desktop is unauthenticated, so keep them set.

Host port 3000 is taken by Grafana, so the desktop publishes 3010 (http) / 3011
(https). Caddy passes WebSockets through automatically.

## Storage

The desktop home dir (`/config`) holds browser cache, downloads, and anything
installed in the session, so it grows. It lives on the **T7** (not the
constrained `local` fs) via a CT 102 bind mount:

| Mount | Host path | CT path |
|-------|-----------|---------|
| mp6 | `/mnt/t7/desktop` | `/opt/desktop/config` |

Owned `110000:110000` on the host (= `10000:10000` in the unprivileged CT, which
matches `PUID/PGID=10000`). T7 is USB, so the home dir is slightly slower than
`local`; fine for light desktop use. If responsiveness matters, swap `/config`
to a dedicated raw disk on `local`.

## GPU

Shares the Intel UHD 620 iGPU with Jellyfin. The render node is passed into CT
102 (`dev0: /dev/dri/renderD128,gid=106`); the compose maps it in, adds the
container user to the render group (`group_add: ["106"]` — without it `abc`
can't open the node at all) and sets `LIBVA_DRIVER_NAME=iHD`.

Two things to know:

- **Hardware OpenGL needs Wayland mode.** The default session is Xvfb (software
  llvmpipe). Setting `PIXELFLUX_WAYLAND=true` switches to a GPU-rendered Wayland
  session (Smithay + Labwc) where GL apps use the iGPU; X apps (Minecraft) run
  via XWayland and inherit it. Needs AVX2 (the i7-8650U has it). Verified:
  `glxinfo` on the session reports "Mesa Intel(R) UHD Graphics 620", GL 4.6 — not
  llvmpipe. No VirtualGL or per-app wrappers needed.

  Gotcha: the compositor runs via `s6-setuidgid abc`, which rebuilds groups from
  `/etc/group` and drops docker's `group_add 106`, so it gets EACCES on
  `renderD128` and falls back to the Pixman software renderer (apps see llvmpipe
  again). The boot script `custom-cont-init.d/10-gpu-fixups.sh` `chmod 666`s the
  render node before the compositor starts to fix this. Confirm hardware GL with
  `glxinfo | grep "OpenGL renderer"` (want UHD 620, not llvmpipe). If it shows
  llvmpipe, check the compositor log:
  `docker logs webtop | grep '\[Wayland\].*GPU'`.

- **The video stream is still CPU-encoded.** This image's pixelflux mode only
  offers `x264enc`/`jpeg` encoders (both CPU); `DRI_NODE` is set but there's no
  VA-API encoder in this pipeline. So the iGPU accelerates *rendering* but not
  stream *encode*. For hardware encode you'd need the GStreamer
  `selkies-egl-desktop` image (NVIDIA-first; Intel unofficial) or a real GPU host.

### Minecraft launcher won't start ("profile in use ... on another computer")

The Mojang launcher is Electron. On each container recreate the hostname
changes, so the single-instance lock it leaves in `/config` (on the T7) looks
like it belongs to "another computer" and the launcher exits (code 21). The
boot script deletes the stale lock (`/config/.minecraft/webcache2/Singleton*`)
on startup. To clear it by hand:
`rm -f /config/.minecraft/webcache2/Singleton*`.

Net: with Wayland mode the iGPU renders Minecraft fine; the remaining cost is CPU
stream encode on a shared 4-core box plus the weak 2017 iGPU. Good for light play;
for serious game streaming use a GPU host.

## Deploy

```shell
# host: T7 dir + bind mount, then restart the CT so mp6 attaches
ssh homelab 'mkdir -p /mnt/t7/desktop && chown 110000:110000 /mnt/t7/desktop'
ssh homelab 'pct set 102 -mp6 /mnt/t7/desktop,mp=/opt/desktop/config'
ssh homelab 'pct reboot 102'                       # restarts the whole stack

# copy compose + env into CT 102, then bring it up
ssh homelab 'pct exec 102 -- docker compose -f selkies-desktop.compose.yml \
  --env-file selkies-desktop.env up -d'

# reload Caddy for the desktop.home route
ssh homelab 'pct exec 102 -- docker exec caddy caddy reload --config /etc/caddy/Caddyfile'
```

## Tuning

- **Password / user:** edit `selkies-desktop.env`, recreate the container.
- **Resolution / scaling:** Selkies adjusts to the browser window; force a size
  with the `MAX_RES`/`DISABLE_*` env vars from the linuxserver Webtop docs.
- **RAM:** CT 102 starts at 8 GB shared across all stacks. XFCE Webtop adds
  ~1–3 GB under use; bump with `pct set 102 -memory 12288` then snapshot if it
  gets tight.
