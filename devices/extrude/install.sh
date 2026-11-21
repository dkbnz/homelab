#!/bin/bash
# Run once by octoprint-provision.service, then removes itself.
# Installs OctoPrint in a venv as user "octoprint", served on :5000.
# Caddy on the homelab proxies http://extrude.home -> 192.168.1.50:5000.
set -euxo pipefail

OP_USER=octoprint
OP_HOME=/home/$OP_USER
VENV=$OP_HOME/oprint

# Armbian's first login creates the user; wait for it.
for i in $(seq 1 360); do id "$OP_USER" >/dev/null 2>&1 && break; sleep 10; done
id "$OP_USER"

hostnamectl set-hostname extrude
sed -i 's/\borangepilite\b/extrude/g' /etc/hosts
grep -q '\bextrude\b' /etc/hosts || echo '127.0.1.1 extrude' >> /etc/hosts

# SSH key login for the user and root.
for d in /root/.ssh "$OP_HOME/.ssh"; do
  install -d -m 700 "$d"
  install -m 600 /root/provision/authorized_keys "$d/authorized_keys"
done
chown -R $OP_USER:$OP_USER "$OP_HOME/.ssh"

# Wait for the network (WiFi can take a while on first boot).
for i in $(seq 1 60); do
  getent hosts deb.debian.org >/dev/null && break
  sleep 5
done

export DEBIAN_FRONTEND=noninteractive
for i in 1 2 3; do apt-get update && break; sleep 20; done
apt-get install -y --no-install-recommends \
  python3 python3-venv python3-dev python3-pip build-essential \
  libyaml-dev libffi-dev zlib1g-dev libjpeg-dev libfreetype-dev git avahi-daemon

# Serial access to the printer (CH340 USB-serial on the Ender 3 V2 Neo).
usermod -aG dialout,tty,video $OP_USER

# /tmp is a 243 MB tmpfs; building wheels (pillow sdist is 47 MB) overflows it.
PIPTMP=$OP_HOME/.cache/pip-build
sudo -u $OP_USER mkdir -p "$PIPTMP"
export TMPDIR=$PIPTMP

sudo -u $OP_USER python3 -m venv "$VENV"
sudo -u $OP_USER TMPDIR="$PIPTMP" "$VENV/bin/pip" install --no-cache-dir --upgrade pip wheel setuptools
for i in 1 2 3; do
  sudo -u $OP_USER TMPDIR="$PIPTMP" "$VENV/bin/pip" install --no-cache-dir OctoPrint && break
  sleep 30
done
# The retry loop above exits 0 even when all three attempts fail.
sudo -u $OP_USER "$VENV/bin/octoprint" --version

# Let OctoPrint restart itself and reboot/shutdown the board from the UI.
cat > /etc/sudoers.d/octoprint <<EOF
$OP_USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart octoprint, /usr/sbin/reboot, /usr/sbin/shutdown
EOF
chmod 440 /etc/sudoers.d/octoprint

install -d -o $OP_USER -g $OP_USER "$OP_HOME/.octoprint"
if [ ! -f "$OP_HOME/.octoprint/config.yaml" ]; then
  cat > "$OP_HOME/.octoprint/config.yaml" <<'EOF'
server:
  commands:
    serverRestartCommand: sudo systemctl restart octoprint
    systemRestartCommand: sudo reboot
    systemShutdownCommand: sudo shutdown -h now
serial:
  port: AUTO
  baudrate: 115200
  autoconnect: true
EOF
  chown $OP_USER:$OP_USER "$OP_HOME/.octoprint/config.yaml"
fi

cat > /etc/systemd/system/octoprint.service <<EOF
[Unit]
Description=OctoPrint
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=$OP_USER
Environment=LC_ALL=C.UTF-8 LANG=C.UTF-8
ExecStart=$VENV/bin/octoprint serve --host 0.0.0.0 --port 5000
Restart=always
RestartSec=5
Nice=-2

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now octoprint

# Done: remove the one-shot unit and the key copy.
systemctl disable octoprint-provision.service
rm -rf /root/provision "$PIPTMP"
echo "OctoPrint provisioning done: http://$(hostname -I | awk '{print $1}'):5000"
