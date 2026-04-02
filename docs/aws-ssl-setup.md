# AWS Deployment with SSL Subdomains

This guide walks you through hosting Rumis AI Lab on AWS with:

- `oui.mydomain.ch` → **Open WebUI** (HTTPS)
- `oc.mydomain.ch` → **OpenClaw** (HTTPS)
- `n8n.mydomain.ch` → **n8n** workflow automation + MCP server (HTTPS)

SSL certificates are issued for free by **Let's Encrypt** and auto-renew every 12 hours.

> **Do NOT create certificates in AWS.** You do not need AWS Certificate Manager (ACM), self-signed certs, or anything from the AWS console. `init-ssl.sh` handles everything — it runs certbot, which contacts Let's Encrypt directly and stores the certs on the EC2 instance. ACM certs cannot be exported to non-AWS services and are unnecessary here.

---

## Quick Run Example (TL;DR)

Complete sequence from zero to working HTTPS. Steps are numbered so you know exactly where you are and what to wait for.

```
[AWS Console]  ~5 min
  1. Launch EC2 t3.small (Ubuntu 24.04), create key pair, open ports 22/80/443
  2. Allocate Elastic IP → associate with instance

[Domain registrar]  ~2 min + wait
  3. Add 3 A records: oui / oc / n8n → <elastic-ip>
  ⏳ WAIT: DNS propagation (1–5 min with low TTL, up to 48 h otherwise)
     Verify: dig +short oui.mydomain.ch  → must return your EC2 IP

[EC2 terminal]
  4. SSH in:
       ssh -i rumis-key.pem ubuntu@<elastic-ip>

  5. Install Docker (~2 min):
       curl -fsSL https://get.docker.com | sudo sh
       sudo usermod -aG docker ubuntu && newgrp docker

  6. Clone and configure:
       git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git
       cd Rumis-AI-Lab
       cp .env.example .env
       nano .env   # fill in API keys + domain names + passwords

  7. Bootstrap SSL (~1–2 min, fully automatic — no manual cert steps):
       bash scripts/init-ssl.sh
     ⏳ WAIT: certbot contacts Let's Encrypt for 3 domains (~15–30 s each)
              No email confirmation, no AWS console action needed.
     ✅ Done when you see:
          SSL setup complete!
            Open WebUI  →  https://oui.mydomain.ch
            OpenClaw    →  https://oc.mydomain.ch
            n8n         →  https://n8n.mydomain.ch

  8. Start services:
       docker compose up -d
     ⏳ WAIT: first run pulls Docker images (~5–10 min depending on connection)
     ⏳ WAIT: healthchecks pass before nginx starts (~2–3 min after images are pulled)
              litellm → open-webui (healthy) + openclaw + n8n (healthy) → nginx starts
     Monitor:
       watch docker compose ps   # all should show "healthy" or "running"
```

### Verify everything works (run from your local machine)

```bash
# 1. HTTP redirect — should return HTTP/1.1 301 (not timeout, not 503)
curl -I http://oui.mydomain.ch

# 2. HTTPS Open WebUI — should return HTTP/2 200
curl -sI https://oui.mydomain.ch | head -3

# 3. HTTPS n8n — should return HTTP/2 200
curl -sI https://n8n.mydomain.ch | head -3

# 4. HTTPS OpenClaw — should return HTTP/2 401 (auth prompt = nginx is working)
curl -sI https://oc.mydomain.ch | head -3

# 5. Check cert issuer (should say "Let's Encrypt" not "self-signed")
curl -vI https://oui.mydomain.ch 2>&1 | grep -E "issuer|subject|expire"
```

### What each error means

| Response | Meaning | Fix |
|----------|---------|-----|
| Timeout / no response | Security Group blocking port 80/443 | Add inbound rules in AWS console |
| `503 SSL not configured yet` | `init-ssl.sh` didn't complete | Check `docker compose logs nginx`, re-run script |
| `502 Bad Gateway` | Backend not healthy yet | Wait 30 s, check `docker compose ps` |
| `curl: (6) Could not resolve` | DNS not propagated yet | Wait and re-check with `dig` |
| Cert issued by self-signed CA | Something intercepted TLS (rare) | Check if Cloudflare proxy is on |

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
 │    ├── oui.mydomain.ch  →  open-webui:8080      (Docker internal)
 │    ├── oc.mydomain.ch   →  openclaw-gateway:18789  (Docker internal)
 │    └── n8n.mydomain.ch  →  n8n:5678             (Docker internal)
 └── certbot              ← auto-renews Let's Encrypt certs
```

All other ports (3000, 4000, 11434, 8081, 18789) are **not exposed** to the internet — only nginx's 80/443 are public.

---

## Step 1 – Launch an EC2 Instance

### Recommended instance type

The Lite AWS setup runs cloud API models only (no local models) so it needs minimal resources.

| Workload | Instance | vCPU | RAM | ~Cost | Notes |
|----------|----------|------|-----|-------|-------|
| **Lite AWS (recommended)** | `t3.small` | 2 | 2 GB | ~$15/mo | API-only, no local models |
| Lite AWS (headroom) | `t3.medium` | 2 | 4 GB | ~$30/mo | Extra RAM for heavy Open WebUI usage |

> For GPU-powered local models, use the [Custom Server](setup-custom-server.md) or [Hybrid](setup-hybrid.md) setup instead.

### UserData (optional — automates server setup)

In the EC2 launch wizard under **Advanced details → User data**, paste the contents of [`scripts/userdata-aws-lite.sh`](../scripts/userdata-aws-lite.sh). This runs once on first boot and automatically:

- Installs Docker
- Creates a 2 GB swap file (prevents OOM on t3.small)
- Clones the repo to `/home/ubuntu/Rumis-AI-Lab`
- Copies `.env.example` → `.env` (ready to fill in)
- Enables automatic security updates

After the instance starts (~3–5 min), SSH in, clone the repo (see Step 4), and go straight to editing `.env`. Skip the manual Docker install steps in Step 3.

> **Private repo:** UserData does not clone the repo automatically — embedding GitHub credentials in UserData is insecure (readable via the instance metadata endpoint). Clone manually after SSH-ing in using a PAT (see Step 4).

### AMI

Use **Ubuntu 24.04 LTS** (search for `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server`).

### Storage

**20 GB** of gp3 EBS is enough for Lite AWS (no local models to store). Increase to 50+ GB if you plan to add local models later.

### Security Group

Open the following **inbound** rules:

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP only | SSH access |
| 80 | TCP | 0.0.0.0/0 | HTTP (Let's Encrypt challenge + redirect) |
| 443 | TCP | 0.0.0.0/0 | HTTPS (Open WebUI + OpenClaw + n8n) |

**Do not open** ports 3000, 4000, 5678, 8081, 11434, 18789 — these are internal only.

### SSH Key Pair

When launching the instance, AWS will ask you to select or create a **key pair**. This is the `.pem` file you'll use to SSH in. If you don't have one:

1. In the EC2 launch wizard → **Key pair** → **Create new key pair**
2. Name it (e.g. `rumis-key`), type RSA, format `.pem`
3. Download it and keep it safe — AWS only gives it to you once
4. `chmod 400 rumis-key.pem` on your local machine before use

### Elastic IP

Assign an **Elastic IP** to the instance so the IP stays fixed across reboots:

1. EC2 → Elastic IPs → Allocate Elastic IP
2. Associate it with your instance

---

## Step 2 – Configure DNS

At your domain registrar (or Route 53), add **three A records** — all pointing to the same Elastic IP:

| Name | Type | Value |
|------|------|-------|
| `oui` | A | `<your-elastic-ip>` |
| `oc` | A | `<your-elastic-ip>` |
| `n8n` | A | `<your-elastic-ip>` |

Wait for DNS to propagate (usually 1–5 minutes with a low TTL, up to 48 h otherwise).

> **Cloudflare users:** If your domain is managed by Cloudflare, set the DNS records to **DNS only** (grey cloud icon), not **Proxied** (orange cloud). Cloudflare's proxy intercepts HTTP traffic and breaks the Let's Encrypt ACME challenge. You can re-enable the proxy after certs are issued if you want, but it's not recommended for this setup (it would add a second SSL termination layer unnecessarily).

**Verify propagation before continuing:**

```bash
dig +short oui.mydomain.ch   # should return your EC2 IP
dig +short oc.mydomain.ch    # should return your EC2 IP
dig +short n8n.mydomain.ch   # should return your EC2 IP
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

**Public repo:**
```bash
git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git
cd Rumis-AI-Lab
```

**Private repo — use a Personal Access Token (PAT):**
```bash
# Generate at: GitHub → Settings → Developer settings → Personal access tokens → Fine-grained
# Scope needed: Contents = Read-only
git clone https://<your-github-username>:<PAT>@github.com/RuminahuiM/Rumis-AI-Lab.git
cd Rumis-AI-Lab
```

> The PAT is only used once for cloning. It is not stored anywhere on the server after the clone completes.

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
N8N_DOMAIN=n8n.mydomain.ch        # ← required; script aborts without this
CERTBOT_EMAIL=you@example.com

# Timezone for n8n workflow scheduling (IANA name)
GENERIC_TIMEZONE=Europe/Zurich    # e.g. America/New_York, Asia/Tokyo

# OpenClaw nginx basic-auth credentials (set before running init-ssl.sh)
OC_AUTH_USER=your-username
OC_AUTH_PASSWORD=your-strong-password

# LiteLLM internal master key (change this from the default for security)
LITELLM_MASTER_KEY=sk-your-secret-master-key
```

---

## Step 5 – Bootstrap SSL Certificates

This script:
1. Writes an HTTP-only nginx config
2. Starts nginx
3. Requests Let's Encrypt certificates for all three domains (oui, oc, n8n)
4. Writes the full HTTPS nginx config and reloads nginx

```bash
# Must be run from inside the project directory
cd ~/Rumis-AI-Lab
bash scripts/init-ssl.sh
```

> **If you get `permission denied` on `docker`:** You need to re-login after Docker was installed so the `docker` group takes effect. Either `exit` and SSH back in, or run `newgrp docker` in the current session, then retry.

The script takes about 1–2 minutes. When it finishes you should see:

```
SSL setup complete!
  Open WebUI  →  https://oui.mydomain.ch
  OpenClaw    →  https://oc.mydomain.ch
  n8n         →  https://n8n.mydomain.ch
  Certificates auto-renew every 12 h via the certbot container.
```

---

## Step 6 – Start All Services

```bash
docker compose up -d
```

This starts: litellm, open-webui, openclaw-gateway, n8n, nginx, certbot. (Ollama and llama.cpp are in the `local-models` profile and won't start — see [Custom Server](setup-custom-server.md) if you need local models.)

### Verify all services are healthy

```bash
docker compose ps
```

Every service should show `healthy` or `running`. If a service shows `unhealthy` or keeps restarting, check its logs:

```bash
docker compose logs <service-name> --tail=30
```

### Verify web access

Run these from your **local machine** (not the EC2 instance):

```bash
# Should redirect to HTTPS (301) — not 503 or timeout
curl -I http://oui.mydomain.ch

# Should return 200 with Open WebUI HTML
curl -sI https://oui.mydomain.ch | head -5

# Should return 200 with n8n HTML
curl -sI https://n8n.mydomain.ch | head -5

# Should return 401 (basic auth prompt) — that means nginx is working
curl -sI https://oc.mydomain.ch | head -5
```

If you get a **timeout** (not a refused connection), the AWS Security Group is blocking port 80/443 — add inbound rules.

If you get a **503** with "SSL not configured yet", init-ssl.sh did not complete — check nginx logs and re-run the script.

If you get a **502 Bad Gateway**, the backend service isn't ready yet — wait 30 seconds and retry, or check `docker compose ps`.

### First-time Open WebUI setup

1. Open `https://oui.mydomain.ch` in your browser
2. Create your admin account on first visit
3. Sign in and start chatting

### First-time n8n setup

1. Open `https://n8n.mydomain.ch`
2. Complete the setup wizard (creates your admin account)
3. See [docs/n8n-mcp-setup.md](n8n-mcp-setup.md) to wire n8n as an MCP tool server for Open WebUI

### First-time OpenClaw setup

See [docs/openclaw-setup.md](openclaw-setup.md) for the one-time onboarding steps.
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

- [x] Ports 3000, 4000, 5678, 8081, 11434, 18789 are **not** in the Security Group
- [x] Port 22 (SSH) is restricted to **your IP only**
- [x] `open-webui` host port is bound to `127.0.0.1` only
- [x] `openclaw-gateway` host port is bound to `127.0.0.1` only
- [x] All API keys are in `.env` (never committed to git)
- [x] `certbot/conf/` is in `.gitignore` (private keys never committed)
- [x] HSTS is enabled with a 2-year max-age
- [x] TLS 1.2+ only (no TLS 1.0/1.1)
- [x] `ENABLE_SIGNUP=false` — new user self-registration is disabled by default
- [ ] After creating your admin account, verify no other users exist (Admin → Settings → Users)

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

The `open-webui` container may still be starting (it waits for LiteLLM to be healthy):
```bash
docker compose ps
docker compose logs open-webui
```

### OpenClaw returns 502 Bad Gateway

OpenClaw needs one-time onboarding before it accepts connections. See `docs/openclaw-setup.md`.
