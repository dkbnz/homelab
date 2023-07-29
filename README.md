# Homelab

>*labroratory (noun)*: a place providing opportunity for experimentation, observation, or practice in a field of study.

This repository contains various scripts and files for my home server. Used for debian based distributions.

## Design Decisions

- Infrastructure-as-code is used where possible, eliminating manual processes and allowing for an iterative approach to infrastructure management.
- Connections to services are managed using a point-to-point VPN ([tailscale](https://github.com/tailscale/tailscale), utilising the opensource control server, [headscale](https://github.com/juanfont/headscale)). This prevents the need for portforwarding & static IPs for the server. It minimises the attack surface by reducing exposed services to the internet.
- Sensitive data, such as terraform state files and keys, are counter-intuitively version controlled right here in this public repository using [transcrypt](https://github.com/elasticdog/transcrypt). It is a bash script that utilises OpenSSL's symmetric cipher routines to seamlessly encrypt/decrypt files specified in the `.gitattributes` file.
- Deployments are made using the [3musketeers](https://3musketeers.io/guide/) pattern, to provide a consistent, OS agnostic, developer experience.

## Setting Up

### Prerequisites (Manual Steps)

- A google cloud project and a service account key downloaded to `terraform/gcp_key.json`.
- Domain to use for the headscale control server.
- Server or VM with a fresh debian install, setup with ssh key access. This will run the services.
- Machine to orchestrate the installation from with the [3musketeers](https://3musketeers.io/guide/) installed:
    - Make
    - Docker
    - Docker Compose

### Setup cloud infrastructure

See [headscale/README.md](./headscale/README.md) for more details about what headscale is.

Update `terraform/terraform.tfvars` with the required values.

```shell
make tf-apply
```

This will initialise a gcp vm instance and install headscale on it.

The terraform should output the external ip of the newly created headscale instance.

### Initialise local services

Ensure you have a machine running that you would like to deploy your services to and that you have ssh key access to it.

```shell
cd ansible
ANSIBLE_SSH_PIPELINING=1 ansible-playbook playbook.yaml -i inventory.yaml --ask-become-pass
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

https://www.reddit.com/r/Tailscale/comments/104y6nq/docker_tailscale_and_caddy_with_https_a_love_story/