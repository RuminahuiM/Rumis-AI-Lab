# Custom Hosted Server Setup

Host the full AI suite on your own hardware or a rented bare-metal/VM server, with HTTPS via Let's Encrypt. Full local model support plus cloud APIs — all behind a proper reverse proxy.

**What runs:**
- Open WebUI at `https://oui.yourdomain.com`
- OpenClaw at `https://oc.yourdomain.com`
- LiteLLM proxy (internal)
- Ollama (local model hosting, GPU recommended)
- llama.cpp (GGUF model server, requires NVIDIA GPU)
- nginx (SSL termination + reverse proxy)
- certbot (auto-renews Let's Encrypt certs every 12 h)

---

## Prerequisites

- A server you control (own hardware, Hetzner, OVH, bare-metal rental, etc.)
- **Docker** installed on the server
- **NVIDIA GPU** with drivers + `nvidia-container-toolkit` (required for llama.cpp; recommended for Ollama)
- A **domain** with DNS pointing at the server's public IP
- Ports **80** and **443** open in any firewall/security group

---

## Step 1 – Install Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
```

For GPU support, install the NVIDIA Container Toolkit:

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Verify
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

---

## Step 2 – Configure DNS

Add two A records at your registrar pointing at your server's public IP:

| Name | Type | Value |
|------|------|-------|
| `oui` | A | `<server-ip>` |
| `oc` | A | `<server-ip>` |

Verify before continuing:
```bash
dig +short oui.yourdomain.com   # must return your server IP
dig +short oc.yourdomain.com
```

---

## Step 3 – Clone and configure

```bash
git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git
cd Rumis-AI-Lab
cp .env.example .env
nano .env
```

Fill in all values:

```env
# API keys (optional — leave empty if not using cloud models)
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...
HF_TOKEN=hf_...   # required for gated HuggingFace model downloads

# Domains (must match your DNS records exactly)
OUI_DOMAIN=oui.yourdomain.com
OC_DOMAIN=oc.yourdomain.com
CERTBOT_EMAIL=you@example.com

# OpenClaw nginx basic-auth (protects oc.<domain> with a password)
OC_AUTH_USER=your-username
OC_AUTH_PASSWORD=your-strong-password
```

Create the OpenClaw data directories:

```bash
mkdir -p openclaw/config openclaw/workspace
```

---

## Step 4 – (Optional) Configure llama.cpp model

Edit `llamacpp-start.sh` to set which GGUF model to download:

```bash
MODELS=(
  "ggml-org/gpt-oss-20b-GGUF|gpt-oss-20b-mxfp4.gguf"
)
```

Update `LLAMA_ARG_MODEL` in `docker-compose.server.yml` to match. See [GPU Configuration](gpu-configuration.md) for tuning `LLAMA_ARG_N_GPU_LAYERS` to your VRAM.

---

## Step 5 – Bootstrap SSL

Run once after DNS has propagated:

```bash
bash scripts/init-ssl.sh
```

This takes ~2 minutes. It requests Let's Encrypt certificates for both domains and generates the full nginx HTTPS config.

> If certbot fails with "domain not resolving to this server", DNS hasn't propagated yet. Wait and retry.

---

## Step 6 – Start all services

```bash
docker compose -f docker-compose.server.yml up -d
```

Check everything started:

```bash
docker compose -f docker-compose.server.yml ps
```

Watch Ollama's model download (happens in the background on first run):

```bash
docker logs -f ollama-init
```

---

## Step 7 – First-time Open WebUI setup

Open `https://oui.yourdomain.com`. Create your admin account on the first visit.

---

## Step 8 – OpenClaw onboarding

```bash
docker compose -f docker-compose.server.yml run --rm --profile cli openclaw-cli onboard
```

- Model provider: `OpenAI-compatible`
- API URL: `http://litellm:4000/v1`
- API Key: `sk-no-key-needed`
- Model: any model from `litellm-config.local.yaml`

Get your dashboard URL:

```bash
docker compose -f docker-compose.server.yml run --rm --profile cli openclaw-cli dashboard --no-open
```

Replace `127.0.0.1:18789` with `oc.yourdomain.com` to access over HTTPS (you'll be prompted for the nginx basic-auth password first).

---

## Using a custom SSL certificate (non-Let's Encrypt)

If your infrastructure uses a corporate CA or wildcard cert instead of Let's Encrypt, skip `init-ssl.sh` and write the nginx config manually:

1. Place your cert and key files somewhere on the server
2. Mount them into nginx via `docker-compose.server.yml`:
   ```yaml
   nginx:
     volumes:
       - ./nginx/conf.d:/etc/nginx/conf.d:ro
       - ./nginx/auth:/etc/nginx/auth:ro
       - /path/to/your/cert.pem:/etc/ssl/cert.pem:ro
       - /path/to/your/key.pem:/etc/ssl/key.pem:ro
   ```
3. Write `nginx/conf.d/app.conf` referencing your cert paths
4. Remove the `certbot` service from `docker-compose.server.yml` (or just don't start it)

---

## Daily operations

```bash
# Start
docker compose -f docker-compose.server.yml up -d

# Stop
docker compose -f docker-compose.server.yml down

# View logs
docker compose -f docker-compose.server.yml logs -f

# Force SSL renewal
docker compose -f docker-compose.server.yml exec certbot certbot renew --force-renewal
docker compose -f docker-compose.server.yml exec nginx nginx -s reload

# Pull a new Ollama model
docker exec ollama ollama pull mistral
```

---

## Troubleshooting

**certbot fails: "domain not resolving"**
→ DNS not yet propagated. Wait and rerun `bash scripts/init-ssl.sh`.

**llama.cpp fails to start**
→ GPU not available or CUDA not configured. Remove `llamacpp` and `llamacpp-init` from the startup command, or just accept the failure — everything else works.

**Open WebUI 502 Bad Gateway**
→ Services still starting. `docker compose -f docker-compose.server.yml ps` — wait for `open-webui` to show healthy.

**OpenClaw shows "Unauthorized" popup**
→ This is the nginx basic-auth — enter your `OC_AUTH_USER` / `OC_AUTH_PASSWORD`.
