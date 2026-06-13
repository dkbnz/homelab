#!/bin/bash
# Recurring backup to the sdc USB disk (/mnt/sdc).
#
# Backs up the irreplaceable homelab data and SKIPS the redownloadable raw media
# (movies/tv/downloads, ~218GB) per the backup policy. What it captures:
#   - CT102 /opt/jellystack/appdata : *arr configs + SQLite DBs + Jellyfin metadata
#                                     + Tailscale sidecar state (the crown jewels)
#   - T7 /mnt/t7 minus the raw video : music, PS4 game data (CUSA00473),
#                                       itemzflow, monitoring data, books
#
# Mirror (not snapshots): each run overwrites the previous backup with --delete.
# Runs from /etc/cron.d/sdc-backup (see install note at the bottom).
#
# Consistency note: this copies live SQLite DBs (*.db + -wal/-shm) without
# stopping anything. SQLite replays the WAL on open, so a restored DB is normally
# consistent; this is a best-effort point-in-time backup, not a quiesced one.
# Stop the stack first if you need a guaranteed-clean copy.
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin  # cron omits /usr/sbin, where pct lives

DEST=/mnt/sdc/backup
LOG=/var/log/sdc-backup.log
exec >>"$LOG" 2>&1
echo "=== $(date '+%F %T') sdc-backup start ==="

if ! mountpoint -q /mnt/sdc; then
    echo "ERROR: /mnt/sdc not mounted - aborting"
    exit 1
fi
mkdir -p "$DEST"

# 1) CT102 appdata. Stream it out of the container with tar (the mp0 volume isn't
#    host-visible while the CT runs), then atomically swap into place so a failed
#    run never leaves a half-copied appdata.
echo "-- appdata --"
TMP="$DEST/.ct102-appdata.new"
rm -rf "$TMP"; mkdir -p "$TMP"
pct exec 102 -- tar c --numeric-owner --warning=no-file-ignored \
    -C /opt/jellystack \
    --exclude='appdata/lost+found' \
    --exclude='appdata/jellyfin/cache' \
    --exclude='appdata/jellyfin/transcodes' \
    --exclude='appdata/*/logs' \
    --exclude='appdata/*/logs.db*' \
    appdata | tar x --numeric-owner -C "$TMP"
rm -rf "$DEST/ct102-appdata"
mv "$TMP/appdata" "$DEST/ct102-appdata"
rmdir "$TMP" 2>/dev/null || true

# 2) T7 data, excluding the redownloadable raw video media and the downloads scratch.
#    Keeps music, CUSA00473 (PS4), itemzflow, monitoring.
echo "-- t7 --"
# rsync exit 24 = "source files vanished before transfer" - benign here, live
# services churn temp files while we copy. Tolerate it.
rsync -a --delete \
    --exclude='/jellystack-media/movies' \
    --exclude='/jellystack-media/tv' \
    --exclude='/jellystack-media/downloads' \
    --exclude='/lost+found' \
    /mnt/t7/ "$DEST/t7/" || { rc=$?; [ "$rc" -eq 24 ] || exit "$rc"; }

echo "=== $(date '+%F %T') done. backup size: $(du -sh "$DEST" | cut -f1) ==="

# --- Install on the host (one-time) ---
#   cp this to /usr/local/bin/sdc-backup.sh ; chmod +x
#   printf '%s\n' '30 3 * * * root /usr/local/bin/sdc-backup.sh' > /etc/cron.d/sdc-backup
# Runs daily at 03:30 (before watchtower's 04:00 image updates).
