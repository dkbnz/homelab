# mail-mcp image: Doug's mailbox as MCP tools for Hermes. Notes: ../../hermes.md.
# Built locally on CT 102 (docker build -t mail-mcp:1 /opt/hermes/mail).
FROM python:3.12-slim
RUN pip install --no-cache-dir "mcp>=1.12,<2" uvicorn
COPY server.py /app/server.py
USER 1000:1000
ENV HOME=/tmp PYTHONUNBUFFERED=1
ENTRYPOINT ["python", "/app/server.py"]
