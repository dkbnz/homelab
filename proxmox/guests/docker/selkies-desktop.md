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

### Cursor and clipboard (Wayland quirks)

- **Invisible cursor (UNRESOLVED in Wayland mode).** In `PIXELFLUX_WAYLAND` mode
  the pointer is invisible. Selkies forwards the cursor to the *client* (the
  "Wayland cursor callback") rather than compositing it into the captured frame,
  so `WLR_NO_HARDWARE_CURSORS=1` does nothing here (selkies' own compositor, not
  labwc, owns the cursor) and the client-side "Use CSS cursors" toggle didn't fix
  it either. The default Xvfb (X11) mode renders the cursor fine. This is a
  Selkies Wayland-mode rough edge; tradeoff is hardware GL (Wayland) vs working
  cursor/clipboard (X11). Not yet solved.
- **Clipboard not syncing:** the server side is fine (Selkies clipboard monitor
  runs; `wl-copy`/`wl-paste` work). The browser Clipboard API needs a permission
  grant and is blocked on the self-signed `:3011` cert. Use the sidebar Clipboard
  box, grant clipboard permission, or serve a trusted cert for auto-sync.

### Launcher: use Prism, not the official Mojang launcher

Use **Prism Launcher** (`/config/prism`, AppImage extracted; desktop icon
"Prism Launcher" via `/config/prism-launch.sh`). It stores its Microsoft login in
its own config under `/config/.local/share/PrismLauncher` (on the T7), so login
**persists with no keyring**. Data and the launcher itself live on `/config`, so
they survive container recreates/updates with no reinstall-on-boot. The wrapper
sets `QT_QPA_PLATFORM=xcb` to run via XWayland (the stable path).

The **official Mojang launcher** (still present as a second icon) re-prompts for
Microsoft login every launch here: it (Electron) stores the MSA token via the OS
keyring (`safeStorage`), and this headless desktop has no working Secret Service.
gnome-keyring auto-unlock in this container proved unreliable (dynamic D-Bus
session bus, activation timeouts), and Electron's `--password-store=basic` didn't
satisfy the launcher. Prism sidesteps all of that — prefer it. (The official
launcher also leaves a stale Electron single-instance lock on recreate; the boot
script clears `/config/.minecraft/webcache2/Singleton*` if you do use it.)

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
- **RAM:** CT 102 is at 12 GB shared across all stacks. Bump with
  `pct set 102 -memory <MB>` then snapshot if it gets tight.

## Performance

The bottleneck is **CPU H.264 encode** (no VA-API in this image's pixelflux mode;
`intel_gpu_top` on the host shows the VCS video engine at 0% while RCS render is
active). Overall CPU isn't saturated — it was single-thread x264 encoding a large
frame. Levers applied / available:

- **Render resolution = the biggest lever.** Encode cost scales with the server
  resolution, which follows the browser window. For full-screen use without a huge
  encode bill, turn on **Use CSS Scaling** (sidebar → Screen Settings) and set a
  **manual resolution** (e.g. 1280x720 or 1600x900): the server renders/encodes
  low and the client stretches to fill the monitor. ~4x less work at 720p vs 1440p.
- **Striped/streaming encode:** `SELKIES_H264_STREAMING_MODE=true` (in the compose)
  re-encodes only changed regions and parallelizes across cores, instead of
  single-thread full-frame.
- **Cores:** CT 102 bumped to 6 (host is 4c/8t) so encode threads + the app
  coexist. `pct set 102 -cores N` applies live.
- **Framerate / CRF:** drop framerate to 30 or raise CRF (sidebar Video Settings)
  if encode still can't keep up.
- Measure with `ssh homelab 'intel_gpu_top'` (render vs idle) and
  `pct exec 102 -- docker exec webtop sh -c "ps -eo pcpu,comm --sort=-pcpu | head"`
  (selkies = encode, java = game). Hardware encode would need the GStreamer
  selkies-egl-desktop image or a GPU host.
