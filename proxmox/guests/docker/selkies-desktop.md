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

- **OpenGL is software (llvmpipe) by default.** The session runs on **Xvfb**, a
  virtual software framebuffer, so GL apps render on the CPU. 3D apps (Minecraft)
  are slow this way. Fix: run them through **VirtualGL** with the EGL backend,
  `vglrun -d egl <app>`, which renders on the UHD 620 (`renderD128`). Verified:
  `vglrun -d egl glxinfo` reports "Mesa Intel(R) UHD Graphics 620", plain glxinfo
  reports llvmpipe. VirtualGL installs into the container layer, which watchtower
  wipes on update, so `/config/custom-cont-init.d/10-virtualgl.sh` (on the T7)
  reinstalls it on every boot; the dir is mounted to `/custom-cont-init.d`
  (source tracked at `selkies-desktop/custom-cont-init.d/10-virtualgl.sh`).
- **Don't vglrun the Minecraft launcher itself.** It's an Electron app;
  VirtualGL breaks its Chromium compositor, giving a blank-but-clickable window.
  So the launcher shortcut runs plain. To accelerate the *game* (not the
  launcher UI), point the installation's **Java executable** at the wrapper
  `/config/vgl-java` (launcher → Installations → Edit → More Options → Java
  executable). The wrapper execs Minecraft's bundled JRE under `vglrun -d egl`,
  so only the game's JVM uses the iGPU. Tracked at `selkies-desktop/vgl-java`.
  Run the game once with the default Java first so the bundled JRE downloads,
  then switch the Java executable to the wrapper.

### Minecraft launcher won't start ("profile in use ... on another computer")

The Mojang launcher is Electron. On each container recreate the hostname
changes, so the single-instance lock it leaves in `/config` (on the T7) looks
like it belongs to "another computer" and the launcher exits (code 21). The
boot script above deletes the stale lock
(`/config/.minecraft/webcache2/Singleton*`) on startup. To clear it by hand:
`rm -f /config/.minecraft/webcache2/Singleton*`.
- **The video stream is CPU-encoded.** This image runs Selkies in
  `websockets`/pixelflux mode, whose only encoders are `x264enc` and `jpeg`
  (both CPU). The GStreamer VA-API/NVENC hardware encoders aren't part of this
  pipeline (the VAAPI init in the logs errors `-22` and is unused). So the iGPU
  accelerates *rendering* via VirtualGL, but not stream *encode*.

Net: a weak 2017 iGPU doing GL render plus a 4-core container doing CPU video
encode (shared with the rest of the stack) makes this marginal for game
streaming. Fine for a light desktop; for real game streaming use a GPU host.

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
