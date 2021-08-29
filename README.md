# Homelab

>*labroratory (noun)*: a place providing opportunity for experimentation, observation, or practice in a field of study.

This repository contains various scripts and files for my home server.
Used for debian based distributions.

Currently installs docker and starts various containers using docker-compose.

## Usage
```shell
git clone git@github.com:dkbarrett/homelab.git
cd homelab
./stacks-up
```

## Hardware

![Front image of homelab](img/front.jpg)
![Back image of homelab](img/back.jpg)

### HP Elitedesk 800 G1 Mini

Running Debian 11 Bullseye. Used as a docker host for experimentation with containerization. Fits in the palm of my hand and sips power.

- 8gb RAM
- i5-4570
- 1 x 128gb SSD

### GL.iNET GL-MT300N-V2 Travel Router

Small travel router running an [OpenWRT](https://openwrt.org/) based firmware out of the box so it is full of features and very extensible. The LEDs, and the physical switch on the side can be customized to perform various actions.

At the moment, The switch is mapped to an OpenVPN client on the router. At the flick of a switch, all traffic on the network gets routed via a VPN.

- 300Mbps (2.4GHz) WiFi - 802.11 b/g/n
- 2 x 10/100M Ethernet Ports
- 1 x USB 2.0 Port
- 128MB RAM
- 16MB ROM
