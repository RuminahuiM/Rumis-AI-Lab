#!/usr/bin/env bash
# =============================================================================
# setup-dgx.sh – One-time DGX Spark setup for Rumis AI Lab backend
#
# Verifies NVIDIA drivers, installs Docker Compose, and clones the repo.
#
# Usage:
#   bash setup-dgx.sh
# =============================================================================
set -euo pipefail

echo "── Checking NVIDIA GPU ──"
if ! command -v nvidia-smi &>/dev/null; then
  echo "ERROR: nvidia-smi not found. Ensure NVIDIA drivers are installed."
  exit 1
fi
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
echo ""

echo "── Checking Docker ──"
if ! command -v docker &>/dev/null; then
  echo "Docker not found. Installing..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  echo "Docker installed. You may need to log out and back in for group changes."
fi
docker --version

echo ""
echo "── Checking NVIDIA Container Toolkit ──"
if ! docker info 2>/dev/null | grep -q "nvidia"; then
  echo "NVIDIA Container Toolkit may not be configured."
  echo "Install it from: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"
  echo "Then run: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
fi

echo ""
echo "── Setup complete ──"
echo "Next steps:"
echo "  1. cd backend/"
echo "  2. cp .env.example .env && edit .env (set HF_TOKEN)"
echo "  3. docker compose up -d"
echo "  4. docker compose logs -f vllm   # watch model download progress"
