# Hermes (CT 102)

Personal AI assistant. It's the
[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) agent
running in-process inside
[nesquena/hermes-webui](https://github.com/nesquena/hermes-webui), one
container, upstream's default layout. It replaced nanobot on 2026-10-09.

It also runs Doug's iCloud inbox and keeps his projects moving on a kanban
board (see Gateway, Profiles, Mail, Kanban below).

Hermes can create, start and stop Docker containers on CT 102. Ask it to spin
up a service and it writes a compose project, starts it, gives it a `.home`
name, and replies with the URL. The rules it follows are in
`hermes/services-AGENTS.md`.

- Web: http://assistant.home (direct `http://192.168.1.30:8787`).
- iPhone: the Hermex app (Uzair Ansar) with server
  `https://homelab-lan.shetland-gamma.ts.net` (see Remote access). Hermex
  needs HTTPS except for `100.64.0.0/10` Tailscale addresses.
- Login: `HERMES_WEBUI_PASSWORD` in `hermes.env` (encrypted via transcrypt).
- Model: OpenRouter, `deepseek/deepseek-v4.1-flash`, key `OPENROUTER_API_KEY`
  in `hermes.env`.
- Telegram: `@nova_pa_ai_bot` via `hermes-gateway` (see Gateway).

## Versions

- `ghcr.io/nesquena/hermes-webui:0.52.443`
- hermes-agent `v0.21.5` (tag `v2026.9.24`), a git checkout at
  `data/hermes-agent`.

The agent is pinned one release back on purpose. The WebUI image runs Python
3.12. Agent v0.21.6 only supports Python 3.14 (every dependency in its
`pyproject.toml` is gated on `python_version >= '3.14'`), so the WebUI installs
none of them and the agent fails with `No module named 'dotenv'`. v0.21.5
supports 3.11 to 3.13. Don't move the agent past v0.21.5 until the WebUI image
moves to Python 3.14.

The WebUI image doesn't install the agent in Docker. On start it looks for the
source at `~/.hermes/hermes-agent` and installs its dependencies into the
image's venv. Without it the UI starts but logs `agent dir: NOT FOUND`.

## Remote access (HTTPS for Hermex)

`tailscale serve` on the subnet router node gives a real Let's Encrypt
certificate for `homelab-lan.shetland-gamma.ts.net`. Nothing to install on the
phone. It is tailnet only (not Funnel).

```shell
ssh homelab 'pct exec 102 -- docker exec ts-subnet-router tailscale serve --bg --https=443 http://192.168.1.30:8787'
ssh homelab 'pct exec 102 -- docker exec ts-subnet-router tailscale serve status'
# remove: ... tailscale serve --https=443 off
```

The serve config is saved in the node's state
(`appdata/ts-subnet-router/state`) and survives restarts. HTTPS certificates
must stay enabled in the Tailscale admin console (DNS -> HTTPS Certificates).
The hostname is public in certificate transparency logs.

The phone needs Tailscale connected. `homelab-lan` is the node name; the URL
reaches the node itself, not a `192.168.1.x` subnet address. A plain
`http://192.168.1.30:8787` or `http://assistant.home` works in a browser but
Hermex rejects it (not HTTPS).

## How service creation works

- `DOCKER_HOST=tcp://docker-proxy:2375`. `docker-proxy`
  (tecnativa/docker-socket-proxy) holds CT 102's Docker socket and is only on
  the internal `dockerapi` network. It allows containers, images, networks,
  volumes, exec and build. It blocks swarm, secrets, plugins, `system` and
  daemon config.
- The WebUI image has no Docker CLI. Static binaries are mounted in from host
  `/mnt/t7/hermes/bin/`: `docker` 29.8.2 (download.docker.com static tgz) and
  the `docker-compose` v5.6.0 CLI plugin (sha256-checked from the GitHub
  release).
- Services live in `/opt/hermes/services/<name>/`. That dir is mounted at the
  same path inside the container, so relative bind mounts in its compose files
  resolve to the same place for the daemon. It's also the default workspace,
  so `services/AGENTS.md` is loaded as context.
- Ports: 8900-8999 on `192.168.1.30`. Reachable over Tailscale through the
  subnet router like everything else.
- `.home` names: Hermes writes `/opt/hermes/caddy/<name>.caddy` and runs
  `docker exec caddy caddy reload`. The jellystack Caddyfile ends with
  `import /etc/caddy/hermes/*.caddy`, and Caddy mounts that dir read-only.
  AdGuard already rewrites `*.home` to `192.168.1.30`.
- Containers Hermes creates carry the label `hermes.managed=true`:
  `docker ps --filter label=hermes.managed=true`.

## Config

`data/config.yaml` is Hermes's full config (~2400 lines, written on first
start), so the repo doesn't keep a copy. Changes from the defaults:

```yaml
model:
  default: "deepseek/deepseek-v4.1-flash"   # image default was anthropic/claude-opus-4.6
  provider: "openrouter"

terminal:
  cwd: "/opt/hermes/services"

approvals:
  mode: manual
  # Hard blocks, checked before approvals or yolo.
  deny:
    - "docker system prune*"
    - "docker volume prune*"
    - "docker image prune*"
    - "docker network prune*"
    - "docker container prune*"
    - "*--privileged*"
    - "*docker.sock*"
    - "*network_mode: host*"
    - "*--network host*"
    - "*--net=host*"
    - "*--pid=host*"
    - "*cloudflared*"
    - "*ngrok*"

mcp_servers:
  vault:
    url: "http://172.31.77.2:8770/mcp"
    headers:
      Authorization: "Bearer ${KB_TOKEN}"
    timeout: 60
```

Edit it in place (it's owned by uid 10000, host 110000; keep it that way),
then `docker restart hermes`. Model and provider can also be changed in the
WebUI settings.

## Memory (Mnemosyne)

Long-term memory uses the [Mnemosyne](https://github.com/mnemosyne-oss/mnemosyne)
provider plugin (`memory.provider: mnemosyne`): local SQLite with FTS5 and
vector search, embeddings computed locally with fastembed
(`BAAI/bge-small-en-v1.5`, ONNX on CPU). Nothing leaves the box. Hermes gets
`mnemosyne_remember`, `mnemosyne_recall`, `mnemosyne_forget` and related
tools. The built-in `MEMORY.md` / `USER.md` memory stays on alongside it.
By default Mnemosyne also autosaves user turns (`memory.mnemosyne.sync_roles`;
`[]` turns that off).

Installed in persistent wrapper mode, as upstream recommends for Docker:

- Side venv: `data/venvs/mnemosyne`, made with the image's Python 3.12 (must
  match the agent's Python). It survives container recreates, unlike the
  image's `/app/venv`.
- Plugin: `data/plugins/mnemosyne/` (wrapper that puts the side venv on
  `sys.path`), plus a bundled skill at
  `data/skills/memory/mnemosyne-memory-override/`.
- Database: `data/mnemosyne/data/mnemosyne.db`.
- Embedding model cache: `data/cache/fastembed` (`FASTEMBED_CACHE_PATH` in
  the compose file; the default `/tmp` is lost on recreate).

Pinned to `mnemosyne-hermes==0.7.3` + `mnemosyne-memory[embeddings]==4.0.0b3`:

- 0.7.4 fails provider construction under Hermes 0.21.5 ("no binding for the
  current home", upstream issues #1114 and #1143, open on 2026-10-09). The
  tools then don't register at all.
- Unpinned pip picks 0.7.2 + core 3.15.1, which don't match
  (`cannot import name 'write_policy_operation'`).

Move to a newer pair once a release fixes #1114.

```shell
# install / repair / upgrade (run inside the container as uid 10000):
ssh homelab 'pct exec 102 -- docker exec -u 10000 hermes sh -c "
  V=/home/hermeswebui/.hermes/venvs/mnemosyne
  [ -x \$V/bin/python ] || /usr/local/bin/python3 -m venv \$V
  \$V/bin/python -m pip install -q mnemosyne-hermes==0.7.3 \"mnemosyne-memory[embeddings]==4.0.0b3\"
  \$V/bin/mnemosyne-hermes install --mode wrapper --force --python \$V/bin/python
  \$V/bin/mnemosyne-hermes status"'
ssh homelab 'pct exec 102 -- docker restart hermes'
ssh homelab 'pct exec 102 -- docker exec -u 10000 hermes /app/venv/bin/hermes memory status'   # Provider: mnemosyne, Status: available
```

If the WebUI image moves to a new Python minor, recreate the side venv with
it (the wrapper refuses a mismatched interpreter). If the tools vanish, check
`docker logs hermes | grep mnemosyne-hermes` for a construction error. Don't
install Mnemosyne from the Hermes plugin catalog: that puts its packages in
`/app/venv`, which is wiped on every recreate.

## Vault (knowledge base)

Hermes reads and edits Doug's vault through the `vault` MCP server (vault-kb,
see `vault.md`) on the `kbnet` network. `4. Archives` and `2. Areas/Identity`
are blocked by the server.

## Gateway (scheduler + Telegram)

The WebUI runs chats but nothing on a schedule. `hermes-gateway` runs the
Hermes gateway against the same `data/`:

- Telegram: `@nova_pa_ai_bot`, `default` profile only, users in
  `TELEGRAM_ALLOWED_USERS`. "Spin up X" from Telegram runs here, so it has the
  same Docker/services/Caddy mounts as `hermes`.
- Cron for every profile (`gateway.multiplex_profiles: true`; log line
  `Cron scheduler will tick 3 profile(s)`). Profiles created later need a
  `docker restart hermes-gateway`.
- The kanban dispatcher (every 60s).

Image `hermes-gateway:v2026.9.24`, built locally from
`hermes/gateway/Dockerfile` (copy at `/opt/hermes/gateway/`):
`python:3.12-slim` + the agent tag installed with `uv pip install -e
"[all,messaging]"` (a plain wheel build fails; `messaging` has
python-telegram-bot). It must match the WebUI: Python 3.12 (Mnemosyne's side
venv), the same agent tag as `data/hermes-agent`, uid 10000 and home
`/home/hermeswebui` (paths recorded in `data/`). Bump both together.

The multiplexed gateway resolves `${VAR}` in a profile's config from that
profile's `.env`, not the container env. `KB_TOKEN` is therefore also in
`data/.env` (and the profile `.env` files, copied on clone); without it the
vault MCP gets 401. Kanban workers are subprocesses with a scrubbed
environment, so `OPENROUTER_API_KEY` must also be in `data/.env` and each
profile's `.env` (otherwise: "No API key found for provider 'openrouter'").
When rotating either key, update `hermes.env` and those `.env` files.

```shell
ssh homelab 'pct exec 102 -- docker compose -f /opt/hermes/compose.yml build hermes-gateway'
ssh homelab 'pct exec 102 -- docker logs --tail 30 hermes-gateway'
ssh homelab 'pct exec 102 -- docker exec hermes-gateway hermes kanban list'
ssh homelab 'pct exec 102 -- docker exec hermes-gateway hermes -p mail cron list'
```

## Profiles

| Profile | Used by | Tools | Can't |
|---------|---------|-------|-------|
| `default` | you: WebUI, Hermex, Telegram | everything, Docker, vault, kanban | read mail |
| `mail` | cron every 10m + 19:30 digest | `mail` MCP (full), vault, kanban, memory | shell, files, web, cron, delegate |
| `pa` | cron 07:30 + kanban worker | web, vault, kanban, memory, `mail` MCP (`draft_new`, `notify` only) | shell, files, read mail, cron, delegate |

- Profiles live in `data/profiles/<name>/` (own `config.yaml`, `.env`,
  `SOUL.md`, memory, cron). `mail` and `pa` were made with
  `hermes profile create <name> --clone` (bot tokens are never cloned).
- Restrictions are `agent.disabled_toolsets` in each profile's config, which
  applies on every surface after per-platform settings.
- Instructions: `hermes/profiles/<name>/SOUL.md` in the repo, copied to
  `data/profiles/<name>/SOUL.md`.
- Mnemosyne: each profile links `plugins/mnemosyne` to the base wrapper
  (`data/plugins/mnemosyne`); each has its own memory DB.
- `kanban` toolset is enabled for `cli`, `cron` (and `telegram` on default).

Why the split: email is written by strangers. The profile that reads it has
no shell, no web and can't send mail, so a prompt-injected email can at worst
misfile mail, write a bad draft, junk a card, or append to a vault note. The
profile with Docker access never reads raw email. `pa` has web but can't read
mail.

## Mail

`mail-mcp` (`hermes/mail/server.py`, image `mail-mcp:1`) holds the iCloud
IMAP/SMTP password (`mail-triage.env`) and exposes fixed tools on the internal
`mailnet` network: `inbox`, `read`, `search`, `folders`, `move`, `flag`,
`mark_done`, `unsubscribe`, `draft_reply`, `draft_new`, `notify`.

- **No send tool.** Replies are saved to Drafts (`[CHECK: ...]` marks where
  the answer is Doug's call); Doug sends them from Mail. That's the approval.
- Unsubscribe is the old safe policy: RFC 8058 one-click POST, else mailto,
  DKIM-signed senders only, never a GET.
- Reads use `BODY.PEEK`, so nothing is marked read.
- Two tokens in `mail-mcp.env`: `MAIL_TOKEN` (all tools; in
  `data/profiles/mail/.env`) and `MAIL_DRAFT_TOKEN` (`draft_new` + `notify`
  only, enforced server-side; in `data/profiles/pa/.env`).
- The inbox is the queue. "Processed" is tracked by the server in
  `mail/state/icloud.json`, not in Hermes's memory. On 2026-10-09 all 973
  messages already in INBOX were marked done, so Hermes started with new mail
  only. To work through the backlog, remove UIDs from `done` in that file.
- `GET /pending` (no auth, `mailnet` only) returns unprocessed UIDs. The
  `inbox` cron job uses it as `--monitor-url`, so the agent only runs when
  there's new mail.
- `notify` posts to Doug's Telegram chat through the bot API (it's the only way
  `mail` and `pa` reach him).

Policy (in `profiles/mail/SOUL.md`): junk + unsubscribe marketing; archive
reference mail and append lasting facts to the matching vault note under
`## From email`; anything needing Doug gets a kanban card (`triage`, assignee
`doug`), a draft reply if needed, a flag, and one notify per run; evening
digest at 19:30.

Logs: `docker logs mail-mcp` (moves, drafts, unsubscribes, notifies) and the
run transcripts in `data/profiles/mail/cron/output/`.

The old `mail-triage` poller was retired on 2026-10-09. Its script and state are
in `/opt/hermes/triage/`.

## Kanban

One board, `data/kanban.db`, shared by all profiles. The WebUI has a Kanban
view; Telegram/CLI use `/kanban` or `hermes kanban ...`.

- Project parent cards and Doug's actions: assignee `doug` (never dispatched).
- `pa` prep work: assignee `pa`, `ready`; the dispatcher spawns a `pa` worker.
- Cards from email: `triage`, assignee `doug`, body starts
  `Source: email (untrusted)`. You promote them.
- `kanban.dispatch_profiles: [mail, pa]` in `data/config.yaml`: the dispatcher
  never spawns `default` (which has Docker), whatever a card says.
- `kanban.max_in_progress: 2`: workers run inside `hermes-gateway` at
  ~400 MB each; the default (8) OOM-killed the container on the first run.
- `kanban.auto_decompose: false`: triage cards are not auto-split and
  dispatched; they wait for you.
- `pa`'s 07:30 review keeps the board in step with `1. Projects` / `2. Areas`,
  queues its own prep work and notifies you with the day's top 3. It logs
  syncs to `1. Projects/Board Sync Log.md`. First run 2026-10-09: 11 project
  cards, 17 actions.

## Storage

Host `/mnt/t7/hermes`, bound into CT 102 as mp11 `/opt/hermes`:

```
/opt/hermes/compose.yml         copy of hermes.compose.yml
/opt/hermes/hermes.env          copy of hermes.env
/opt/hermes/mail-triage.env     copy of mail-triage.env (iCloud creds for mail-mcp)
/opt/hermes/mail-mcp.env        copy of mail-mcp.env
/opt/hermes/gateway/            hermes-gateway Dockerfile
/opt/hermes/mail/               mail-mcp Dockerfile + server.py, state/ (uid 1000, host 101000)
/opt/hermes/data/               ~/.hermes in the container, uid 10000 (host 110000):
                                config.yaml, sessions, memories, skills, webui/,
                                hermes-agent/ (agent checkout), mnemosyne/ (memory DB),
                                venvs/mnemosyne + plugins/mnemosyne (memory plugin),
                                profiles/{mail,pa}, kanban.db
/opt/hermes/services/           compose projects Hermes creates, + AGENTS.md
/opt/hermes/caddy/              <name>.caddy snippets for Caddy
/opt/hermes/bin/                docker CLI + compose plugin
/opt/hermes/triage/             retired mail-triage poller + state
```

`data/` also has leftovers from the first deploy, when the official
hermes-agent image ran the Telegram gateway (`gateway_state.json`,
`gateway.*`, `logs/gateways/`, `kanban*`). They're unused.

`sdcard-backup.sh` mirrors `/mnt/t7/hermes` to the SD card with the rest of
the T7.

## Security

- **Hermes is effectively root in CT 102.** Through the Docker API it can start
  a container that bind-mounts any CT 102 path. That includes the T7 data,
  every stack's `.env`, and the vault (including folders vault-kb blocks). It
  can also stop or delete any container. The proxy can't filter bind mounts.
  What limits it:
  - The rules in `services/AGENTS.md` (only touch `hermes.managed=true`
    containers, no mounts outside the service dir). These are instructions,
    not enforcement.
  - `approvals.deny` hard-blocks prunes, privileged/host-network containers,
    socket mounts and tunnels.
  - `approvals.mode: manual`. Commands Hermes classes as dangerous need
    approval in the UI. Ordinary `docker run` / `compose up` do not.
  - The WebUI password.
- It cannot reach the Proxmox host. CT 102 is unprivileged and has no host
  credentials.
- Prompt injection is the main risk. Raw email only reaches the `mail`
  profile (no shell, no web, no send). `default` still reads text that came
  from email second-hand: kanban cards (`Source: email (untrusted)`) and vault
  `## From email` sections. `pa` reads them too and has web, so a crafted email
  could in principle steer `pa` into leaking vault text through a web
  request. Cards from email stay in triage until you promote them, which is
  the main guard against that.
- Kill switch: `docker stop hermes hermes-gateway docker-proxy`. Without the
  proxy, Hermes has no Docker access. `docker stop mail-mcp` cuts mail off;
  `hermes -p mail cron pause <id>` (in `hermes-gateway`) pauses inbox runs.
- LAN/Tailscale only. `tailscale serve` is tailnet only; never use Funnel.

## Deploy

```shell
ssh homelab 'mkdir -p /mnt/t7/hermes/{data,services,caddy,triage/state,bin} && chown 100000:100000 /mnt/t7/hermes && chown 110000:110000 /mnt/t7/hermes/{data,services,caddy} && chown -R 101000:101000 /mnt/t7/hermes/triage'
ssh homelab 'pct set 102 -mp11 /mnt/t7/hermes,mp=/opt/hermes'   # hotplugs, no restart
# docker CLI + compose plugin:
ssh homelab 'cd /mnt/t7/hermes/bin && curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-29.8.2.tgz | tar -xz --strip-components=1 docker/docker && curl -fsSL -o docker-compose https://github.com/docker/compose/releases/download/v5.6.0/docker-compose-linux-x86_64 && chmod 755 docker docker-compose'
# agent source (pinned, see Versions):
ssh homelab 'pct exec 102 -- docker run --rm -u 10000:10000 -v /opt/hermes/data:/d alpine/git clone -q --depth 1 --branch v2026.9.24 https://github.com/NousResearch/hermes-agent.git /d/hermes-agent'
# copy hermes.compose.yml -> /opt/hermes/compose.yml, hermes.env, mail-triage.env,
# hermes/services-AGENTS.md -> /opt/hermes/services/AGENTS.md (chown 10000),
# hermes/mail-triage.py -> /opt/hermes/triage/ (chown 1000)
ssh homelab 'pct exec 102 -- docker compose -f /opt/hermes/compose.yml up -d'
# then apply the Config section above and docker restart hermes,
# and the tailscale serve command under Remote access
```

## Upgrade

Watchtower skips Hermes and docker-proxy (labels). Upstream says to upgrade
the WebUI and agent together. Pick a WebUI release and the agent release
from the same date, and check the agent's `pyproject.toml` still supports the
WebUI image's Python (see Versions).

```shell
# agent: replace the checkout
ssh homelab 'pct exec 102 -- sh -c "rm -rf /opt/hermes/data/hermes-agent && docker run --rm -u 10000:10000 -v /opt/hermes/data:/d alpine/git clone -q --depth 1 --branch <tag> https://github.com/NousResearch/hermes-agent.git /d/hermes-agent"'
# webui: bump the tag in hermes.compose.yml and copy it in. Then recreate
# (not restart): the image skips dependency install while its venv marker exists.
ssh homelab 'pct exec 102 -- docker compose -f /opt/hermes/compose.yml up -d --force-recreate hermes'
```

Check the startup log shows `agent dir ... [ok]` and no `missing modules`.

Then rebuild the gateway on the same agent tag (`HERMES_REF` in
`hermes/gateway/Dockerfile`, and the image tag in `hermes.compose.yml`):

```shell
ssh homelab 'pct exec 102 -- sh -c "cd /opt/hermes && docker compose build hermes-gateway && docker compose up -d hermes-gateway"'
```

## nanobot (retired)

nanobot was stopped on 2026-10-09, not removed. Its container and image are
still on CT 102 and its data (config, sessions, memory, source checkout) is
still on host `/mnt/t7/nanobot` (mp9 `/opt/nanobot`). Its old `mail-triage`
container was removed. To remove nanobot for good:

```shell
ssh homelab 'pct exec 102 -- sh -c "docker rm nanobot && docker rmi nanobot:v0.3.5"'
ssh homelab 'pct set 102 -delete mp9'   # then rm -r /mnt/t7/nanobot once sure
```
