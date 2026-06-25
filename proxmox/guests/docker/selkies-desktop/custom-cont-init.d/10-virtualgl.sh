#!/bin/bash
# selkies-desktop boot fixups (runs as root via the LSIO cont-init system).
# Deployed to /opt/desktop/config/custom-cont-init.d/ on CT 102 (the T7), mounted
# into the container at /custom-cont-init.d (see selkies-desktop.compose.yml).
#
# 1) Reinstall VirtualGL. It installs into the container layer, which watchtower
#    wipes on image update, so reinstall on each boot. vglrun -d egl renders
#    OpenGL on /dev/dri/renderD128 (UHD 620) instead of software llvmpipe.
if ! command -v vglrun >/dev/null 2>&1; then
  cd /tmp
  curl -fsSL -o vgl.deb https://github.com/VirtualGL/virtualgl/releases/download/3.1.4/virtualgl_3.1.4_amd64.deb \
    && dpkg -i vgl.deb 2>/dev/null || apt-get install -y -f -qq
fi
# 2) Clear the Minecraft launcher stale Electron single-instance lock. The
#    container hostname changes on every recreate, so a lock left in /config
#    (on the T7) from a previous instance blocks startup with "profile in use
#    ... on another computer". Safe to drop at boot - nothing is running yet.
rm -f /config/.minecraft/webcache2/Singleton* 2>/dev/null
