#!/bin/bash
# selkies-desktop boot fixups (runs as root via the LSIO cont-init system, before
# the Wayland compositor service starts). Deployed to
# /opt/desktop/config/custom-cont-init.d/ on CT 102 (the T7), mounted at
# /custom-cont-init.d (see selkies-desktop.compose.yml).
#
# Make the iGPU render node openable by the Wayland compositor. With
# PIXELFLUX_WAYLAND=true the compositor renders on the GPU (DRI3/EGL), but it runs
# via s6-setuidgid abc, which rebuilds supplementary groups from /etc/group and
# drops docker's group_add 106 -> EACCES on renderD128 -> falls back to the Pixman
# software renderer (apps then see llvmpipe). World-rw on the node inside this
# isolated container fixes it so the compositor uses the UHD 620.
chmod 666 /dev/dri/renderD128 2>/dev/null
# Clear stale Minecraft launcher Electron single-instance lock (the container
# hostname changes on recreate, which otherwise blocks the launcher).
rm -f /config/.minecraft/webcache2/Singleton* 2>/dev/null
