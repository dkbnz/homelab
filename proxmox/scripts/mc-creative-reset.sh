#!/usr/bin/env bash
# Daily reset of the minecraft-creative prototyping world on CT 102.
#
# Stops the container, wipes only the world region data (world, world_nether,
# world_the_end) inside the mc-creative-data volume, then restarts so itzg
# regenerates a fresh flat world. server.properties, ops, whitelist, and any
# plugins are left intact.
#
# Installed to /usr/local/bin/mc-creative-reset.sh on the Proxmox host and run
# at 09:00 Pacific/Auckland by /etc/cron.d/mc-creative-reset.
set -euo pipefail

CTID=102
CONTAINER=minecraft-creative
VOL=mc-creative-data

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

log "stopping ${CONTAINER}"
pct exec "${CTID}" -- docker stop "${CONTAINER}"

log "wiping world data in volume ${VOL}"
pct exec "${CTID}" -- docker run --rm -v "${VOL}:/data" alpine \
  sh -c 'rm -rf /data/world /data/world_nether /data/world_the_end'

log "starting ${CONTAINER}"
pct exec "${CTID}" -- docker start "${CONTAINER}"

log "done"
