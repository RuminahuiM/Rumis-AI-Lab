#!/usr/bin/env bash
# =============================================================================
# up-local.sh – Start the Local Full setup (LAN, no SSL)
#
# What this starts:
#   ollama, ollama-init, llamacpp-init, llamacpp,
#   litellm, open-webui, openclaw-gateway
#
# Access after startup:
#   Open WebUI  →  http://<lan-ip>:3000
#   OpenClaw    →  http://<lan-ip>:18789
#
# Find your LAN IP:  hostname -I | awk '{print $1}'
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f ".env" ]]; then
  echo "ERROR: .env not found. Copy .env.example and fill in your API keys:"
  echo "  cp .env.example .env && nano .env"
  exit 1
fi

mkdir -p openclaw/config openclaw/workspace

echo "Starting Rumis AI Lab (Local Full)..."
docker compose -f docker-compose.local.yml up -d

echo ""
echo "=========================================================================="
echo "  Stack is starting. First run may take a few minutes."
echo ""
echo "  Ollama downloads llama3.2:3b in the background — check progress:"
echo "    docker logs -f ollama-init"
echo ""
LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "<your-lan-ip>")
echo "  Open WebUI  →  http://${LAN_IP}:3000"
echo "  OpenClaw    →  http://${LAN_IP}:18789"
echo ""
echo "  Check service status: docker compose -f docker-compose.local.yml ps"
echo "=========================================================================="
