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
#   - Clones this repo to /home/ubuntu/Rumis-AI-Lab
#   - Copies .env.example → .env (ready for you to fill in)
#   - Creates required OpenClaw directories
#   - Enables automatic security updates
#
# What you still do manually after SSH-ing in:
#   1. nano /home/ubuntu/Rumis-AI-Lab/.env   — fill in API keys, domains, passwords
#   2. Verify DNS (nslookup oui.yourdomain.com → must return this server's IP)
#   3. bash scripts/init-ssl.sh              — issues Let's Encrypt certs
#   4. docker compose up -d                  — start all services

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

# ── Clone repository ─────────────────────────────────────────────────────────
REPO_DIR=/home/ubuntu/Rumis-AI-Lab
if [ ! -d "$REPO_DIR" ]; then
    sudo -u ubuntu git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git "$REPO_DIR"
fi

# ── Prepare .env ─────────────────────────────────────────────────────────────
if [ ! -f "$REPO_DIR/.env" ]; then
    sudo -u ubuntu cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
fi

# ── Required directories ─────────────────────────────────────────────────────
sudo -u ubuntu mkdir -p "$REPO_DIR/openclaw/config" "$REPO_DIR/openclaw/workspace"

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
echo "  nano $REPO_DIR/.env                   # fill in API keys, domains, passwords"
echo "  cd $REPO_DIR && bash scripts/init-ssl.sh   # after DNS is propagated"
echo "  docker compose up -d"
