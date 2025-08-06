#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

wget --output-document=headscale.deb \
  https://github.com/juanfont/headscale/releases/download/v${version}/headscale_${version}_linux_amd64.deb

dpkg --install headscale.deb

cat << 'EOF' > /etc/headscale/config.yaml
${config}
EOF

systemctl enable headscale
systemctl start headscale
