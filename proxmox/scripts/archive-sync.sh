#!/bin/bash
# Keep the offline Kiwix archive (/mnt/t7/archive/zim) at the newest ZIM builds.
#
# Reads /usr/local/etc/archive-zim-list.txt (tracked in the repo as
# proxmox/guests/docker/archive/zim-list.txt). Each entry is <dir>/<prefix>; the
# newest <prefix>_YYYY-MM.zim in https://download.kiwix.org/zim/<dir>/ is
# downloaded, checked against its published .sha256, moved into place, and the
# older build is deleted. kiwix-serve in CT 102 is restarted if anything changed.
#
# Space: a new build is fully downloaded before the old one is removed, so a
# refresh needs free space for the whole file (119G for Wikipedia maxi). An entry
# is skipped with an ERROR line if the T7 would drop below MARGIN_GB free.
#
# Usage: archive-sync.sh [filter]   # optional grep -E filter on list entries
# Runs monthly from /etc/cron.d/archive-sync (install note at the bottom).
set -uo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin  # cron omits /usr/sbin

LIST=/usr/local/etc/archive-zim-list.txt
DEST=/mnt/t7/archive/zim
BASE=https://download.kiwix.org/zim
MARGIN_GB=20
LOG=/var/log/archive-sync.log
FILTER=${1:-.}

[ -t 1 ] || exec >>"$LOG" 2>&1
exec 9>/run/archive-sync.lock
flock -n 9 || { echo "another archive-sync is running - exiting"; exit 0; }
echo "=== $(date '+%F %T') archive-sync start (filter: $FILTER) ==="

if ! mountpoint -q /mnt/t7; then
    echo "ERROR: /mnt/t7 not mounted - aborting"
    exit 1
fi
mkdir -p "$DEST"

changed=0
errors=0
declare -A listings

while read -r entry; do
    dir=${entry%%/*}
    prefix=${entry#*/}

    # One directory listing per Kiwix dir per run.
    if [ -z "${listings[$dir]+x}" ]; then
        listings[$dir]=$(wget -qO- "$BASE/$dir/") || { echo "ERROR: cannot list $dir"; errors=$((errors+1)); continue; }
    fi
    latest=$(grep -oE "\"${prefix}_[0-9]{4}-[0-9]{2}\.zim\"" <<<"${listings[$dir]}" | tr -d '"' | sort | tail -1)
    if [ -z "$latest" ]; then
        echo "ERROR: no build found for $entry"
        errors=$((errors+1))
        continue
    fi
    if [ -f "$DEST/$latest" ]; then
        continue
    fi

    url="$BASE/$dir/$latest"
    # Last Content-Length wins (redirects come first). Kept as a string: awk
    # prints large numbers like 127G in float notation, which bash can't do maths on.
    size=$(wget -q --spider -S "$url" 2>&1 | awk 'tolower($1)=="content-length:" {n=$2} END {print n}' | tr -dc '0-9')
    size=${size:-0}
    avail=$(df --output=avail -B1 "$DEST" | tail -1)
    part="$DEST/.$latest.part"
    have=$(stat -c %s "$part" 2>/dev/null || echo 0)
    need=$(( size - have + MARGIN_GB * 1024**3 ))
    if [ "$size" -eq 0 ] || [ "$avail" -lt "$need" ]; then
        echo "ERROR: skipping $latest: size $((size/1024**3))G, free $((avail/1024**3))G, margin ${MARGIN_GB}G"
        errors=$((errors+1))
        continue
    fi

    echo "-- $latest ($((size/1024**3))G) --"
    if ! wget -c -q -O "$part" "$url"; then
        echo "ERROR: download failed for $latest (partial kept, resumes next run)"
        errors=$((errors+1))
        continue
    fi
    want=$(wget -qO- "$url.sha256" | awk '{print $1}')
    got=$(sha256sum "$part" | awk '{print $1}')
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
        echo "ERROR: sha256 mismatch for $latest (want '$want', got '$got') - deleted"
        rm -f "$part"
        errors=$((errors+1))
        continue
    fi
    chown 110000:110000 "$part"
    mv "$part" "$DEST/$latest"
    changed=1
    for old in "$DEST/${prefix}"_[0-9][0-9][0-9][0-9]-[0-9][0-9].zim; do
        [ "$old" = "$DEST/$latest" ] || [ ! -f "$old" ] || { echo "   removing old $(basename "$old")"; rm -f "$old"; }
    done
done < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$LIST" | grep -v '^$' | grep -E -- "$FILTER")

if [ "$changed" -eq 1 ]; then
    echo "-- restarting kiwix --"
    pct exec 102 -- docker restart kiwix || errors=$((errors+1))
fi
echo "=== $(date '+%F %T') done. errors: $errors, archive: $(du -sh "$DEST" | cut -f1), T7 free: $(df -h --output=avail /mnt/t7 | tail -1 | tr -d ' ') ==="
[ "$errors" -eq 0 ]

# --- Install on the host (one-time) ---
#   cp this to /usr/local/bin/archive-sync.sh ; chmod +x
#   cp proxmox/guests/docker/archive/zim-list.txt /usr/local/etc/archive-zim-list.txt
#   printf '%s\n' '30 0 2 * * root /usr/local/bin/archive-sync.sh' > /etc/cron.d/archive-sync
# Runs on the 2nd of each month at 00:30. A big refresh can run past the 03:30
# SD card backup; that is fine, the backup skips .part files.
