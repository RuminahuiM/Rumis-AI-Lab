#!/bin/bash
# EC2 UserData script for Rumis AI Lab — Lite AWS setup
#
# Paste this into "Advanced details → User data" when launching the EC2 instance.
# Runs once as root on first boot. Takes ~3–5 minutes.
# Progress is logged to: /var/log/userdata.log
#
# What this does automatically:
#   - Updates system packages
#   - Installs Docker (official method) and enables it on boot
#   - Creates a 2 GB swap file (important: t3.small only has 2 GB RAM)
#   - Creates required OpenClaw directories (once repo is cloned)
#   - Enables automatic security updates
#
# What you still do manually after SSH-ing in:
#   1. Clone the repo (see note below about private repos)
#   2. cp .env.example .env && nano .env   — fill in API keys, domains, passwords
#   3. Verify DNS (nslookup oui.yourdomain.com → must return this server's IP)
#   4. bash scripts/init-ssl.sh            — issues Let's Encrypt certs
#   5. docker compose up -d               — start all services
#
# NOTE — private repo / git clone:
#   The git clone is NOT done here because embedding GitHub credentials in
#   UserData is insecure (visible in AWS console + instance metadata endpoint).
#   Clone manually after SSH-ing in using a Personal Access Token (PAT):
#
#     git clone https://<your-github-username>:<PAT>@github.com/RuminahuiM/Rumis-AI-Lab.git
#
#   Generate a PAT at: GitHub → Settings → Developer settings → Personal access tokens
#   Scope needed: repo (read-only is enough for cloning)
#
#   If you later make the repo public, you can remove the PAT from the URL:
#     git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git

set -euo pipefail
exec > >(tee /var/log/userdata.log | logger -t userdata) 2>&1

echo "=== Rumis AI Lab UserData starting: $(date) ==="

# ── System update ────────────────────────────────────────────────────────────
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install useful tools (git already on Ubuntu 24.04 but listed for clarity)
apt-get install -y git curl nano htop

# ── Docker ───────────────────────────────────────────────────────────────────
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# ── Swap (2 GB) ──────────────────────────────────────────────────────────────
# t3.small has 2 GB RAM. LiteLLM + Open WebUI + n8n + nginx can exceed this
# during image pulls or under load. Swap prevents OOM kills.
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "Swap: 2 GB created and enabled"
fi

# ── Required directories ─────────────────────────────────────────────────────
# Created here so they exist when the user clones the repo.
# (openclaw bind-mounts these; Docker will error if they're missing)
sudo -u ubuntu mkdir -p /home/ubuntu/Rumis-AI-Lab/openclaw/config \
                        /home/ubuntu/Rumis-AI-Lab/openclaw/workspace

# ── Automatic security updates ───────────────────────────────────────────────
apt-get install -y unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' \
    > /etc/apt/apt.conf.d/51rumis-no-reboot
dpkg-reconfigure --priority=low unattended-upgrades

# ── Done ─────────────────────────────────────────────────────────────────────
PUBLIC_IP=$(curl -sf --connect-timeout 5 http://169.254.169.254/latest/meta-data/public-ipv4 || echo "<unknown>")

echo ""
echo "=== UserData complete: $(date) ==="
echo ""
echo "Instance IP : $PUBLIC_IP"
echo "Repo        : $REPO_DIR"
echo ""
echo "Next steps:"
echo "  ssh -i your-key.pem ubuntu@$PUBLIC_IP"
echo "  git clone https://<user>:<PAT>@github.com/RuminahuiM/Rumis-AI-Lab.git ~/Rumis-AI-Lab"
echo "  cd ~/Rumis-AI-Lab"
echo "  cp .env.example .env && nano .env      # fill in API keys, domains, passwords"
echo "  # verify DNS, then:"
echo "  bash scripts/init-ssl.sh"
echo "  docker compose up -d"
