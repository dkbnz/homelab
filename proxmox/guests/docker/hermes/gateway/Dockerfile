# Hermes gateway: scheduler (cron + kanban dispatcher) and Telegram, sharing
# the WebUI container's Hermes home. Notes: ../../hermes.md, Gateway.
#
# Matches the WebUI image on purpose:
#   - Python 3.12 (the Mnemosyne side venv in data/venvs/mnemosyne was made
#     with 3.12 and its wrapper refuses another minor version)
#   - the same agent release as data/hermes-agent (bump both together)
#   - uid 10000 and home /home/hermeswebui, so absolute paths recorded in
#     data/ (venvs, plugin wrapper) resolve the same way
#
# Build (in CT 102):
#   docker build -t hermes-gateway:v2026.9.24 /opt/hermes/gateway
FROM python:3.12-slim

ARG HERMES_REF=v2026.9.24

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Editable install with uv, the same way the WebUI image installs the agent
# (a plain wheel build of this tag fails).
RUN git clone --depth 1 --branch "$HERMES_REF" https://github.com/NousResearch/hermes-agent.git /opt/hermes-agent \
 && pip install --no-cache-dir uv \
 && uv pip install --system --no-cache -e "/opt/hermes-agent[all,messaging]"

RUN groupadd -g 10000 hermeswebui \
 && useradd -u 10000 -g 10000 -d /home/hermeswebui -m -s /bin/sh hermeswebui

USER 10000:10000
ENV HOME=/home/hermeswebui \
    HERMES_HOME=/home/hermeswebui/.hermes
WORKDIR /opt/hermes/services

ENTRYPOINT ["hermes"]
CMD ["gateway", "run", "--replace"]
