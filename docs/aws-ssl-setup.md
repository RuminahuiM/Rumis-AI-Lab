# AWS Deployment with SSL Subdomains

This guide walks you through hosting Rumis AI Lab on AWS with:

- `oui.mydomain.ch` → **Open WebUI** (HTTPS)
- `oc.mydomain.ch` → **OpenClaw** (HTTPS)

SSL certificates are issued for free by **Let's Encrypt** and auto-renew every 12 hours.

---

## Architecture Overview

```
Internet
    │
    ▼
AWS Security Group (ports 80, 443 open)
    │
    ▼
EC2 Instance
 ├── nginx (port 80/443)  ← SSL termination + reverse proxy
 │    ├── oui.mydomain.ch  →  open-webui:8080  (Docker internal)
 │    └── oc.mydomain.ch   →  openclaw-gateway:18789  (Docker internal)
 └── certbot              ← auto-renews Let's Encrypt certs
```

All other ports (3000, 4000, 11434, 8081, 18789) are **not exposed** to the internet — only nginx's 80/443 are public.

---

## Step 1 – Launch an EC2 Instance

### Recommended instance type

| Workload | Instance | vCPU | RAM | Notes |
|----------|----------|------|-----|-------|
| CPU-only | `t3.xlarge` | 4 | 16 GB | Cheapest viable option |
| GPU (local models) | `g4dn.xlarge` | 4 | 16 GB | 1× NVIDIA T4 (16 GB VRAM) |
| GPU (larger models) | `g4dn.2xlarge` | 8 | 32 GB | Better for 20B+ models |

### AMI

Use **Ubuntu 24.04 LTS** (search for `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server`).

### Storage

Add at least **100 GB** of gp3 EBS storage (models are large).

### Security Group

Open the following **inbound** rules:

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP only | SSH access |
| 80 | TCP | 0.0.0.0/0 | HTTP (Let's Encrypt challenge + redirect) |
| 443 | TCP | 0.0.0.0/0 | HTTPS (Open WebUI + OpenClaw) |

**Do not open** ports 3000, 4000, 8081, 11434, 18789 — these are internal only.

### Elastic IP

Assign an **Elastic IP** to the instance so the IP stays fixed across reboots:

1. EC2 → Elastic IPs → Allocate Elastic IP
2. Associate it with your instance

---

## Step 2 – Configure DNS

At your domain registrar (or Route 53), add two **A records**:

| Name | Type | Value |
|------|------|-------|
| `oui` | A | `<your-elastic-ip>` |
| `oc` | A | `<your-elastic-ip>` |

Wait for DNS to propagate (usually 1–5 minutes with a low TTL, up to 48 h otherwise).

**Verify propagation before continuing:**

```bash
dig +short oui.mydomain.ch   # should return your EC2 IP
dig +short oc.mydomain.ch    # should return your EC2 IP
```

---

## Step 3 – Set Up the EC2 Instance

SSH into your instance:

```bash
ssh -i your-key.pem ubuntu@<elastic-ip>
```

### Install Docker

```bash
# Update packages
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu
newgrp docker   # reload group without re-login

# Verify
docker version
```

### (GPU instances only) Install NVIDIA Container Toolkit

```bash
# Add NVIDIA repo
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify GPU access
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

---

## Step 4 – Deploy the Project

### Clone the repository

```bash
git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git
cd Rumis-AI-Lab
```

### Configure environment

```bash
cp .env.example .env
nano .env   # or your preferred editor
```

Fill in **all** values:

```env
# API keys
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...
HF_TOKEN=hf_...        # optional but needed for GGUF model downloads

# SSL domains – must match your DNS records exactly
OUI_DOMAIN=oui.mydomain.ch
OC_DOMAIN=oc.mydomain.ch
CERTBOT_EMAIL=you@example.com

# OpenClaw nginx basic-auth credentials (set before running init-ssl.sh)
OC_AUTH_USER=your-username
OC_AUTH_PASSWORD=your-strong-password
```

---

## Step 5 – Bootstrap SSL Certificates

This script:
1. Writes an HTTP-only nginx config
2. Starts nginx
3. Requests Let's Encrypt certificates for both domains
4. Writes the full HTTPS nginx config and reloads nginx

```bash
bash scripts/init-ssl.sh
```

The script takes about 1–2 minutes. When it finishes you should see:

```
SSL setup complete!
  Open WebUI  →  https://oui.mydomain.ch
  OpenClaw    →  https://oc.mydomain.ch
  Certificates auto-renew every 12 h via the certbot container.
```

---

## Step 6 – Start All Services

```bash
docker compose up -d
```

This starts: ollama, llamacpp, litellm, open-webui, openclaw-gateway, nginx, certbot.

Check everything is running:

```bash
docker compose ps
```

### First-time Open WebUI setup

1. Open `https://oui.mydomain.ch` in your browser
2. Create your admin account on first visit
3. Sign in and start chatting

### First-time OpenClaw setup

See `docs/openclaw-setup.md` for the one-time onboarding steps.
The UI is at `https://oc.mydomain.ch`.

---

## Maintenance

### View logs

```bash
# All services
docker compose logs -f

# Just nginx
docker compose logs -f nginx

# Just certbot renewals
docker compose logs -f certbot
```

### Manually force certificate renewal

```bash
docker compose exec certbot certbot renew --force-renewal
docker compose exec nginx nginx -s reload
```

### Update all images

```bash
docker compose pull
docker compose up -d
```

---

## Security Checklist

- [x] Ports 3000, 4000, 8081, 11434, 18789 are **not** in the Security Group
- [x] Port 22 (SSH) is restricted to **your IP only**
- [x] `open-webui` host port is bound to `127.0.0.1` only
- [x] `openclaw-gateway` host port is bound to `127.0.0.1` only
- [x] All API keys are in `.env` (never committed to git)
- [x] `certbot/conf/` is in `.gitignore` (private keys never committed)
- [x] HSTS is enabled with a 2-year max-age
- [x] TLS 1.2+ only (no TLS 1.0/1.1)
- [ ] Enable Open WebUI user registration controls (Admin → Settings → Users)
- [ ] Consider setting `ENABLE_SIGNUP=false` after creating your accounts

### Optional: automatic security updates

```bash
sudo apt-get install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

---

## Troubleshooting

### certbot fails: "Domain not resolving to this server"

DNS has not propagated yet. Wait and retry:
```bash
dig +short oui.mydomain.ch   # must show your EC2 IP
bash scripts/init-ssl.sh     # retry
```

### nginx fails to start

Check the config syntax:
```bash
docker compose exec nginx nginx -t
docker compose logs nginx
```

### Certificate already exists but expired / needs renew

```bash
docker compose run --rm certbot renew --force-renewal
docker compose exec nginx nginx -s reload
```

### Open WebUI returns 502 Bad Gateway

The `open-webui` container may still be starting (it waits for Ollama):
```bash
docker compose ps
docker compose logs open-webui
```

### OpenClaw returns 502 Bad Gateway

OpenClaw needs one-time onboarding before it accepts connections. See `docs/openclaw-setup.md`.
