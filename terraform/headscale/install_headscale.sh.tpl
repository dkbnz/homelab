#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

wget --output-document=headscale.deb \
  https://github.com/juanfont/headscale/releases/download/v${version}/headscale_${version}_linux_amd64.deb

dpkg --install headscale.deb

echo "${config}" > /etc/headscale/config.yaml

systemctl enable headscale
systemctl start headscale
