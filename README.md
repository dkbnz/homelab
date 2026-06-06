# Homelab

>*labroratory (noun)*: a place providing opportunity for experimentation, observation, or practice in a field of study.

This repository contains various scripts and files for my home server. Used for debian based distributions.

## Topology

The lab runs [Proxmox VE](https://www.proxmox.com/) on a single mini PC, hosting one
VM and two LXC containers:

| ID  | Type | Name     | Address        | Purpose                            |
|-----|------|----------|----------------|------------------------------------|
| 100 | VM   | haos12.4 | DHCP           | Home Assistant OS                  |
| 101 | LXC  | adguard  | `192.168.1.20` | AdGuard Home DNS / ad blocking     |
| 102 | LXC  | docker   | `192.168.1.30` | Docker host (watchtower + stacks)  |

The host, guest configs, and rebuild steps are documented in [`proxmox/`](proxmox/).
Service stacks that can be deployed onto the Docker LXC live in [`services/`](services/)
and [`docker-compose-service.yml`](docker-compose-service.yml). The Backblaze B2
backup bucket is managed under [`terraform/`](terraform/).

## Design Decisions

- Infrastructure-as-code is used where possible, eliminating manual processes and allowing for an iterative approach to infrastructure management.
- Connections to services are managed using a point-to-point VPN ([Tailscale](https://tailscale.com/), via a subnet router on the Docker LXC). This prevents the need for portforwarding & static IPs for the server. It minimises the attack surface by reducing exposed services to the internet. (An earlier self-hosted [headscale](https://github.com/juanfont/headscale) control server on GCP was decommissioned in 2026.)
- Sensitive data, such as terraform state files and keys, are counter-intuitively version controlled right here in this public repository using [transcrypt](https://github.com/elasticdog/transcrypt). It is a bash script that utilises OpenSSL's symmetric cipher routines to seamlessly encrypt/decrypt files specified in the `.gitattributes` file.
- Deployments are made using the [3musketeers](https://3musketeers.io/guide/) pattern, to provide a consistent, OS agnostic, developer experience.

## Setting Up

### Prerequisites (Manual Steps)

- A Backblaze B2 account and application key in `terraform/terraform.tfvars` (for the backup bucket).
- A [Tailscale](https://tailscale.com/) account; the lab joins the tailnet via a subnet router on the Docker LXC (see `proxmox/guests/docker/jellystack.md`).
- Server or VM with a fresh debian install, setup with ssh key access. This will run the services.
- Machine to orchestrate the installation from with the [3musketeers](https://3musketeers.io/guide/) installed:
    - Make
    - Docker
    - Docker Compose

### Setup cloud infrastructure

Terraform manages the Backblaze B2 backup bucket and its application key.
Update `terraform/terraform.tfvars` with the required values.

```shell
make tf-init
make tf-apply
```

### Set up the Proxmox guests

The host and its guests (Home Assistant VM, AdGuard and Docker LXCs) are documented
in [`proxmox/`](proxmox/), including how each was built and how to rebuild it. Pull
the live state back into the repo at any time with:

```shell
proxmox/scripts/snapshot.sh
```

### Deploy service stacks onto the Docker LXC

The Docker LXC (CT 102) runs containers managed by docker compose. The Ansible
playbook below installs Docker and deploys `docker-compose-service.yml` to a target
host. It predates the Proxmox setup (where the helper script already provides Docker),
so it is optional - point `ansible/inventory.yaml` at the Docker LXC (`192.168.1.30`)
if you want to use it.

```shell
cd ansible
ANSIBLE_SSH_PIPELINING=1 ansible-playbook playbook.yaml -i inventory.yaml --ask-become-pass
```

## Hardware

![Front image of homelab](img/front.jpg)
![Back image of homelab](img/back.jpg)

### Mini PC (Proxmox host)

Intel Core i7-8650U mini PC running Proxmox VE 8. Fits in the palm of my hand and sips power.

- 16gb RAM
- i7-8650U (8 threads)
- 64gb SanDisk SSD (boot, `local-lvm`)
- 931gb Samsung T7 (data, passed through to the Docker LXC)

### GL.iNET GL-MT300N-V2 Travel Router

Small travel router running an [OpenWRT](https://openwrt.org/) based firmware out of the box so it is full of features and very extensible. The LEDs, and the physical switch on the side can be customized to perform various actions.

At the moment, The switch is mapped to an OpenVPN client on the router. At the flick of a switch, all traffic on the network gets routed via a VPN.

- 300Mbps (2.4GHz) WiFi - 802.11 b/g/n
- 2 x 10/100M Ethernet Ports
- 1 x USB 2.0 Port
- 128MB RAM
- 16MB ROM

https://www.reddit.com/r/Tailscale/comments/104y6nq/docker_tailscale_and_caddy_with_https_a_love_story/