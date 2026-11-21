#!/bin/bash
# Recurring backup to the onboard SD card (/mnt/sdcard, mmcblk0p1, 953G ext4).
#
# Replaces the old sdc USB HDD, which was physically removed 2026-06-25 (its USB
# port was reused for the T7 at SuperSpeed). Backs up only the irreplaceable
# homelab data and SKIPS what is redownloadable or regenerable:
#   - raw video media (jellystack-media/movies, tv, downloads, ~218GB) - redownloadable
#   - /mnt/t7/docker - Docker images/layers, rebuilt on the next image pull
#   - /mnt/t7/valheim/server - Valheim game files, redownloaded by steamcmd
# What it captures (all host-visible under /mnt/t7 after the 2026-06-25 move of
# CT102 appdata + docker off `local` onto T7 bind mounts):
#   - appdata : *arr configs + SQLite DBs + Jellyfin metadata + Tailscale sidecar
#               state (the crown jewels)
#   - jellystack-media minus raw video : the music library (Navidrome/Lidarr)
#   - books (CWA + Shelfmark), monitoring (Prometheus TSDB + Grafana),
#     CUSA00473 + itemzflow (PS4 game data), desktop (Selkies home)
#   - archive : Kiwix ZIMs + LLM models + offline installers (~170G). Redownloadable
#               today, but the point of it is to survive losing the internet, so it
#               is backed up. In-progress downloads (.part) are skipped.
#
# Mirror (not snapshots): each run overwrites the previous backup with --delete.
# Runs from /etc/cron.d/sdcard-backup (see install note at the bottom).
#
# Consistency note: this copies live SQLite DBs (*.db + -wal/-shm) without
# stopping anything. SQLite replays the WAL on open, so a restored DB is normally
# consistent; this is a best-effort point-in-time backup, not a quiesced one.
# Stop the stack first if you need a guaranteed-clean copy.
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin  # cron omits /usr/sbin

DEST=/mnt/sdcard/backup
LOG=/var/log/sdcard-backup.log
exec >>"$LOG" 2>&1
echo "=== $(date '+%F %T') sdcard-backup start ==="

if ! mountpoint -q /mnt/sdcard; then
    echo "ERROR: /mnt/sdcard not mounted - aborting"
    exit 1
fi
mkdir -p "$DEST"

# Single mirror of /mnt/t7, dropping the redownloadable/regenerable trees.
# appdata is a host bind mount under /mnt/t7 now, so no in-container tar is needed.
# Leading-slash excludes are anchored to the transfer root (/mnt/t7).
echo "-- t7 (irreplaceable only) --"
# rsync exit 24 = "source files vanished before transfer" - benign here, live
# services churn temp files while we copy. Tolerate it.
rsync -aH --delete --numeric-ids \
    --exclude='/docker' \
    --exclude='/jellystack-media/movies' \
    --exclude='/jellystack-media/tv' \
    --exclude='/jellystack-media/downloads' \
    --exclude='/appdata/jellyfin/cache' \
    --exclude='/appdata/jellyfin/transcodes' \
    --exclude='/appdata/*/logs' \
    --exclude='/appdata/*/logs.db*' \
    --exclude='/valheim/server' \
    --exclude='/zomboid/workshop' \
    --exclude='/archive/zim/.*.part' \
    --exclude='/lost+found' \
    /mnt/t7/ "$DEST/" || { rc=$?; [ "$rc" -eq 24 ] || exit "$rc"; }

echo "=== $(date '+%F %T') done. backup size: $(du -sh "$DEST" | cut -f1) ==="

# --- Install on the host (one-time) ---
#   cp this to /usr/local/bin/sdcard-backup.sh ; chmod +x
#   printf '%s\n' '30 3 * * * root /usr/local/bin/sdcard-backup.sh' > /etc/cron.d/sdcard-backup
# Runs daily at 03:30 (before watchtower's 04:00 image updates).
