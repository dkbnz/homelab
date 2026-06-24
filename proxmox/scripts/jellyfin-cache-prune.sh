#!/usr/bin/env bash
# Prune regenerable Jellyfin cache on CT 102 to keep the appdata loop
# (/dev/loop0, ~7.8G) above Jellyfin's 2GiB startup free-space gate. Jellyfin
# refuses to start (FTL "insufficient free space ... Required: 2GiB") and serves
# 5XX through caddy when /config has under 2GiB free. The loop is backed by the
# host root fs (`local`), which runs hot. See proxmox/guests/docker/jellystack.md.
#
# Deleted data is all regenerable: transcode segments and old logs. Metadata
# (data/metadata) and image cache are left alone. Runs daily at 04:15, just
# before the 04:30 `pct fstrim 102` so the freed blocks get trimmed back to the
# host in the same window.
set -euo pipefail

pct exec 102 -- sh -c '
  d=/opt/jellystack/appdata/jellyfin
  # Transcode segments: delete only files untouched for >2h so an in-progress
  # stream (continuously written) is never pulled out from under playback.
  [ -d "$d/cache/transcodes" ] && find "$d/cache/transcodes" -type f -mmin +120 -delete
  # Logs older than 14 days.
  [ -d "$d/log" ] && find "$d/log" -type f -name "*.log*" -mtime +14 -delete
  true
'
