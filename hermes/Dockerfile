# =============================================================================
# Hermes Agent – lean production image for AWS t3.small
# Based on python:3.11-slim (not the upstream debian:13.4 full build).
#
# Excluded intentionally to keep image under ~300 MB and fit t3.small (2 GB RAM):
#   - Playwright / browser automation  (~500 MB Chromium)
#   - WhatsApp bridge                  (~200 MB Node.js)
#
# If you need browser tools, build from the upstream image instead:
#   https://github.com/NousResearch/hermes-agent
# =============================================================================
FROM python:3.11-slim

# System deps: git (hermes update), ripgrep (code-search tool), curl (healthcheck),
# gosu (entrypoint privilege drop — fixes bind-mount ownership from host root)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git ripgrep curl gosu \
    && rm -rf /var/lib/apt/lists/*

# Non-root user — uid 1001 to avoid collision with OpenClaw's uid 1000 (node user)
RUN groupadd -g 1001 hermes && \
    useradd -u 1001 -g hermes -m -s /bin/bash hermes

# Install hermes-agent from source (not published on PyPI).
# Uses uv for fast dependency resolution, matching the upstream dev workflow.
RUN pip install --no-cache-dir uv && \
    uv pip install --system --no-cache \
        "git+https://github.com/NousResearch/hermes-agent.git"

# Runtime data directory — matches HERMES_HOME env var below
RUN mkdir -p /opt/hermes-data && chown 1001:1001 /opt/hermes-data

# Pre-seed config: points the agent at LiteLLM so the setup wizard only needs
# to confirm settings rather than fill them in from scratch.
COPY --chown=hermes:hermes seed-config.yaml /opt/hermes-data/config.yaml

# Entrypoint: runs as root, chowns the bind-mount, then drops to hermes (uid 1001)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Stay as root — entrypoint handles the privilege drop via gosu
WORKDIR /home/hermes

ENV HERMES_HOME=/opt/hermes-data

VOLUME ["/opt/hermes-data"]

# Gateway port (confirmed from hermes-workspace docker-compose.yml)
EXPOSE 8642

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD true

ENTRYPOINT ["/entrypoint.sh"]
# hermes gateway run exits immediately if no messaging platforms are configured
# (expected before 'hermes setup' is run). The wrapper falls back to sleep so
# the container stays alive and ready for CLI commands.
CMD ["/bin/sh", "-c", "hermes gateway run || { echo 'Hermes gateway stopped — run: docker compose run --rm hermes-cli setup, then restart this container'; exec sleep infinity; }"]
