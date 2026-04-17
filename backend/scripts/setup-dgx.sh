#!/usr/bin/env bash
# =============================================================================
# setup-dgx.sh – Preflight checks for Rumis AI Lab VLLM backend on DGX Spark
#
# Verifies GPU, Docker, and NVIDIA Container Toolkit before VLLM deployment.
# Safe to run multiple times — only installs what's missing.
#
# Usage:
#   bash backend/scripts/setup-dgx.sh
# =============================================================================
set -euo pipefail

RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BOLD=$'\e[1m'; RESET=$'\e[0m'

pass() { echo "${GREEN}✓${RESET} $*"; }
warn() { echo "${YELLOW}!${RESET} $*"; }
fail() { echo "${RED}✗${RESET} $*"; exit 1; }
info() { echo "${BOLD}──${RESET} $*"; }

# ─── 1. NVIDIA driver ─────────────────────────────────────────────────────────
info "Checking NVIDIA driver"
if ! command -v nvidia-smi &>/dev/null; then
  fail "nvidia-smi not found. Install NVIDIA drivers (DGX OS usually ships with them)."
fi
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | head -n1)
pass "Driver: ${DRIVER_VERSION}   GPU: ${GPU_INFO}"

# ─── 2. Docker ────────────────────────────────────────────────────────────────
info "Checking Docker"
if ! command -v docker &>/dev/null; then
  warn "Docker not found. Installing via get.docker.com..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  warn "You must log out and back in (or 'newgrp docker') before continuing."
  exit 0
fi

if ! docker info &>/dev/null; then
  fail "Docker is installed but not accessible. Try: sudo usermod -aG docker \$USER && newgrp docker"
fi
pass "Docker: $(docker --version | awk '{print $3}' | tr -d ,)"

# ─── 3. NVIDIA Container Toolkit ──────────────────────────────────────────────
info "Checking NVIDIA Container Toolkit"
if ! docker info 2>/dev/null | grep -qi "nvidia"; then
  warn "nvidia runtime not registered with Docker."
  echo "   Installing NVIDIA Container Toolkit..."
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
  pass "NVIDIA Container Toolkit installed"
else
  pass "NVIDIA Container Toolkit is configured"
fi

# ─── 4. GPU-in-container smoke test ───────────────────────────────────────────
info "Running GPU smoke test in a container"
if docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -L &>/tmp/gpu-test.log; then
  pass "GPU is accessible from containers:"
  grep "^GPU" /tmp/gpu-test.log | sed 's/^/    /'
else
  fail "GPU test failed. Output:
$(cat /tmp/gpu-test.log)"
fi

# ─── 5. docker compose ────────────────────────────────────────────────────────
info "Checking docker compose"
if ! docker compose version &>/dev/null; then
  fail "docker compose (v2) not available. Upgrade Docker to get the Compose plugin."
fi
pass "docker compose: $(docker compose version --short)"

# ─── 6. .env check ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")"
info "Checking backend/.env"
if [[ ! -f "${BACKEND_DIR}/.env" ]]; then
  warn ".env not found. Copy .env.example and set HF_TOKEN:"
  echo "    cp ${BACKEND_DIR}/.env.example ${BACKEND_DIR}/.env"
  echo "    nano ${BACKEND_DIR}/.env"
elif ! grep -qE '^HF_TOKEN=hf_[A-Za-z0-9]' "${BACKEND_DIR}/.env"; then
  warn "HF_TOKEN does not look set in ${BACKEND_DIR}/.env"
  echo "    Edit and paste your token from https://huggingface.co/settings/tokens"
else
  pass ".env is configured"
fi

echo ""
echo "${GREEN}${BOLD}── All preflight checks passed ──${RESET}"
echo ""
echo "Next steps:"
echo "  1. cd ${BACKEND_DIR}"
echo "  2. Ensure .env has a valid HF_TOKEN (needed for gated Gemma model)"
echo "  3. docker compose up -d"
echo "  4. docker compose logs -f vllm    # watch model download (~5–15 min)"
echo "  5. curl http://localhost:8000/v1/models"
