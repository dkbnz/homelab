# Running services on the homelab

You run on CT 102, the Docker host of Doug's homelab (Proxmox LXC,
192.168.1.30). The `docker` CLI in your container talks to CT 102's Docker
daemon. Doug reaches services over the LAN and Tailscale, never the internet.

## Creating a service

When Doug asks for a new service:

1. Pick a short lowercase name. Use `/opt/hermes/services/<name>/`.
2. Write `/opt/hermes/services/<name>/compose.yml`:
   - Prefer the project's official image. Use a release tag, not `latest`,
     when the project publishes them.
   - `container_name: <name>` (and `<name>-<role>` for extra containers).
   - `restart: unless-stopped`, `TZ=Pacific/Auckland`.
   - Label every container `hermes.managed=true`.
   - Data in relative bind mounts under the service dir (`./data:/data`).
     Never bind-mount anything outside `/opt/hermes/services/<name>/`.
   - Publish the web port on a free host port in 8900-8999. Check first:
     `docker ps --format '{{.Ports}}' | grep -o ':89[0-9][0-9]'`.
   - Set `mem_limit` (start at 512m). CT 102 has 9G shared by ~40 containers.
   - Secrets: generate with `openssl rand -hex 24`, put them in
     `/opt/hermes/services/<name>/.env`, reference with `${VAR}`. Tell Doug
     where they are; don't paste them into chat unless asked.
3. `docker compose -f /opt/hermes/services/<name>/compose.yml up -d`, then
   check `docker compose ... ps` and `docker logs <name>` until it is healthy.
4. Give it a `.home` name: write `/opt/hermes/caddy/<name>.caddy`:
   ```
   http://<name>.home {
       reverse_proxy 192.168.1.30:<port>
   }
   ```
   then `docker exec caddy caddy reload --config /etc/caddy/Caddyfile`.
   DNS for `*.home` already points at Caddy. Don't reuse a name that is
   already in `docker exec caddy cat /etc/caddy/Caddyfile`.
5. Test it: `curl -sI http://192.168.1.30:<port>`.
6. Reply with: URL (`http://<name>.home`, and `http://192.168.1.30:<port>`
   over Tailscale), login details location, and the service dir.

Removing a service: `docker compose -f .../compose.yml down`, delete its
`.caddy` file and reload Caddy. Ask before deleting its `data/`.

## Hard rules

- Only stop, restart, recreate or remove containers labelled
  `hermes.managed=true`. Everything else (jellyfin, the *arr stack, caddy,
  tailscale, monitoring, vault, mail-mcp, docker-proxy, hermes-gateway,
  yourself) belongs
  to Doug's repo. You may read their logs and status. If one needs a restart,
  ask Doug first and say why.
- Never `docker system prune`, `docker volume prune`, `docker image prune -a`,
  or delete images/volumes/networks you didn't create.
- Never run containers with `privileged`, `network_mode: host`, `pid: host`,
  extra capabilities, or the Docker socket mounted.
- Never publish ports to the internet or set up port forwarding, tunnels
  (cloudflared, ngrok) or public DNS. Remote access is Tailscale only.
- Don't install crypto miners, torrent clients outside the existing stack, or
  anything that scans the network.
