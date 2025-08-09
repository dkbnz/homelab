#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures
export DEBIAN_FRONTEND=noninteractive

# Update system packages first
apt-get update
apt-get upgrade -y

# Install security tools
apt-get install -y fail2ban ufw 

# Configure UFW firewall
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 50443/tcp # Headscale gRPC
ufw --force enable

# Configure fail2ban for SSH protection
cat << 'FAIL2BAN_EOF' > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
FAIL2BAN_EOF

systemctl enable fail2ban
systemctl start fail2ban

# Install Headscale
wget --output-document=headscale.deb \
  https://github.com/juanfont/headscale/releases/download/v${version}/headscale_${version}_linux_amd64.deb

dpkg --install headscale.deb

cat << 'HEADSCALE_CONFIG_EOF' > /etc/headscale/config.yaml
${config}
HEADSCALE_CONFIG_EOF

systemctl enable headscale
systemctl start headscale
