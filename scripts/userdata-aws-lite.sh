#!/usr/bin/env bash
# =============================================================================
# userdata-aws-lite.sh – EC2 UserData bootstrap for Rumis AI Lab (lite/API-only)
#
# Runs as root at first boot. Installs Docker + Compose, configures swap,
# enables SSM agent. The actual repo clone + stack deploy is done later
# via SSM Run Command (see .github/workflows/deploy.yml).
# =============================================================================
set -euo pipefail
exec > >(tee /var/log/userdata.log | logger -t userdata) 2>&1
echo "=== UserData started at $(date) ==="

# ── 1. System update ──────────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -yq --no-install-recommends

# ── 2. Swap (4 GB) ────────────────────────────────────────────────────────────
if [[ ! -f /swapfile ]]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap  /swapfile
  swapon  /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "vm.swappiness=10" >> /etc/sysctl.conf
  sysctl -p
  echo "Swap: 4 GB created"
fi

# ── 3. Docker Engine ─────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  apt-get install -yq --no-install-recommends ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -yq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  usermod -aG docker ubuntu
  echo "Docker installed: $(docker --version)"
fi

# ── 4. AWS SSM Agent ─────────────────────────────────────────────────────────
# Already pre-installed on Ubuntu 22.04+/24.04 AMIs; ensure it's running.
systemctl enable amazon-ssm-agent 2>/dev/null || true
systemctl start  amazon-ssm-agent 2>/dev/null || true

# ── 5. Useful CLI tools ───────────────────────────────────────────────────────
apt-get install -yq --no-install-recommends git jq unzip htop

echo "=== UserData complete at $(date) ==="
