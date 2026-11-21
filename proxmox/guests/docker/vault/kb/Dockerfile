# vault-kb image: MCP knowledge-base server over the vault. Notes: ../../vault.md.
# Built locally on CT 102 (docker build -t vault-kb:1 /opt/vault-stack/kb).
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/* \
    && git config --system --add safe.directory '*'
RUN pip install --no-cache-dir "mcp>=1.12,<2" "fastembed>=0.5,<1" "pypdf>=5,<7" "numpy<3" uvicorn
COPY server.py /app/server.py
USER 1000:1000
ENV HOME=/tmp PYTHONUNBUFFERED=1
ENTRYPOINT ["python", "/app/server.py"]
