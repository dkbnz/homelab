#!/usr/bin/env bash
# Pull the live Proxmox guest configuration into this repo so it can be committed.
# Run from anywhere; writes into proxmox/guests/. Requires `ssh homelab` access (root on the Proxmox host).
#
# Usage: proxmox/scripts/snapshot.sh
set -euo pipefail

SSH_HOST="${SSH_HOST:-homelab}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUESTS="$REPO_ROOT/proxmox/guests"

# Strip the volatile/host-specific lines that should not be tracked (UUIDs, MACs,
# vmgenid, creation metadata, helper-script HTML descriptions).
strip() {
  grep -vE '^(smbios1|vmgenid|meta|description|hwaddr|net0:.*hwaddr|efidisk0:.*$)' \
    | sed -E 's/,hwaddr=[^,]*//; s/virtio=[0-9A-Fa-f:]+/virtio/'
}

echo "Snapshotting VM 100 (Home Assistant OS)..."
ssh "$SSH_HOST" 'qm config 100' | grep -vE '^(smbios1|vmgenid|meta|description):' \
  | sed -E 's/,hwaddr=[^,]*//; s/virtio=[0-9A-Fa-f:]+/virtio/' \
  > /tmp/haos.cfg
echo "  -> review /tmp/haos.cfg against $GUESTS/100-haos.conf"

echo "Snapshotting CT 101 (AdGuard)..."
ssh "$SSH_HOST" 'pct config 101' | grep -vE '^(description):' \
  | sed -E 's/,hwaddr=[^,]*//' > /tmp/adguard.cfg
echo "  -> review /tmp/adguard.cfg against $GUESTS/101-adguard.conf"

echo "Snapshotting CT 102 (Docker)..."
ssh "$SSH_HOST" 'pct config 102' | grep -vE '^(description):' \
  | sed -E 's/,hwaddr=[^,]*//' > /tmp/docker.cfg
echo "  -> review /tmp/docker.cfg against $GUESTS/102-docker.conf"

echo "Pulling AdGuard Home config..."
ssh "$SSH_HOST" 'pct exec 101 -- cat /opt/AdGuardHome/AdGuardHome.yaml' \
  > "$GUESTS/adguard/AdGuardHome.yaml"
echo "  -> wrote $GUESTS/adguard/AdGuardHome.yaml (encrypted by transcrypt on commit)"

echo
echo "Done. The .conf files are reviewed by hand because they carry comments;"
echo "diff the /tmp/*.cfg files against them and apply any real changes."
echo "Then: git add -p && git commit"
