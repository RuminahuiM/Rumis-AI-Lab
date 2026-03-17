# Hybrid Setup (AWS + Remote GPU Server)

Run the lightweight stack (Open WebUI, OpenClaw, LiteLLM) cheaply on AWS while offloading heavy local model inference to a separate GPU server — your own hardware or a rented GPU box (Hetzner GPU, Lambda Labs, vast.ai, etc.).

```
                    Internet
                       │
              ┌────────┴────────┐
              │                 │
      AWS EC2 (t3.small)    GPU Server
      ├── nginx (HTTPS)     ├── nginx (HTTPS)
      ├── open-webui        ├── ollama:11434
      ├── openclaw          └── llamacpp:8080
      └── litellm  ──────────────────────────▶ http://gpu.yourdomain.com
```

LiteLLM on the AWS side routes local model requests over HTTPS to the GPU server. No open ports on the GPU server except 80/443.

---

## Prerequisites

- **AWS side:** AWS account, a domain (for HTTPS on both sides), `t3.small` or larger
- **GPU server side:** Any Linux server with Docker + NVIDIA GPU + a subdomain (e.g. `gpu.yourdomain.com`)
- Both servers need ports 80 and 443 open

---

## Part 1 – Set up the GPU Server

The GPU server runs only Ollama and llama.cpp, exposed over HTTPS via nginx. It does **not** run Open WebUI or OpenClaw.

### 1a – Install Docker + NVIDIA Container Toolkit

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker

# NVIDIA runtime
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker
```

### 1b – Point DNS

Add an A record for your GPU server:

| Name | Type | Value |
|------|------|-------|
| `gpu` | A | `<gpu-server-ip>` |

### 1c – Run Ollama and llama.cpp

On the GPU server, create a minimal compose file (`~/gpu-server/docker-compose.yml`):

```yaml
services:
  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

  llamacpp:
    image: ghcr.io/ggml-org/llama.cpp:server-cuda
    restart: unless-stopped
    ports:
      - "127.0.0.1:8081:8080"
    volumes:
      - llamacpp_models:/models:ro
    environment:
      LLAMA_ARG_MODEL: "/models/your-model.gguf"
      LLAMA_ARG_HOST: "0.0.0.0"
      LLAMA_ARG_PORT: "8080"
      LLAMA_ARG_N_GPU_LAYERS: "28"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

  nginx:
    image: nginx:1.27-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./certbot/www:/var/www/certbot:ro
      - ./certbot/conf:/etc/letsencrypt:ro

  certbot:
    image: certbot/certbot:latest
    restart: unless-stopped
    volumes:
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    entrypoint: /bin/sh -c "trap exit TERM; while :; do certbot renew --quiet; sleep 12h & wait $${!}; done"

volumes:
  ollama_data:
  llamacpp_models:
```

### 1d – Bootstrap SSL on the GPU server

Create a minimal `scripts/init-ssl-gpu.sh` (adjust domains):

```bash
GPU_DOMAIN=gpu.yourdomain.com
CERTBOT_EMAIL=you@example.com

mkdir -p nginx/conf.d certbot/www certbot/conf

# HTTP-only config for ACME challenge
cat > nginx/conf.d/gpu.conf <<NGINX
server {
    listen 80;
    server_name ${GPU_DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 503; }
}
NGINX

docker compose up -d nginx
sleep 5

docker compose run --rm certbot certonly \
  --webroot --webroot-path=/var/www/certbot \
  --email "${CERTBOT_EMAIL}" --agree-tos --no-eff-email \
  -d "${GPU_DOMAIN}"

# HTTPS config proxying Ollama and llamacpp
cat > nginx/conf.d/gpu.conf <<NGINX
server {
    listen 80;
    server_name ${GPU_DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl;
    http2 on;
    server_name ${GPU_DOMAIN};
    ssl_certificate     /etc/letsencrypt/live/${GPU_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${GPU_DOMAIN}/privkey.pem;

    # Ollama – routed via /ollama/
    location /ollama/ {
        proxy_pass http://ollama:11434/;
        proxy_set_header Host \$host;
    }

    # llama.cpp – routed via /llamacpp/
    location /llamacpp/ {
        proxy_pass http://llamacpp:8080/;
        proxy_set_header Host \$host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX

docker compose exec nginx nginx -s reload
echo "GPU server ready at https://${GPU_DOMAIN}"
```

Pull your Ollama models:
```bash
docker exec ollama ollama pull llama3.2:3b
```

---

## Part 2 – Set up the AWS Side

### 2a – Deploy AWS Lite as normal

Follow [docs/aws-ssl-setup.md](aws-ssl-setup.md) to deploy the Lite AWS stack. You'll have `oui.yourdomain.com` and `oc.yourdomain.com` running.

### 2b – Add the GPU server to your `.env`

```env
# (existing vars)
ANTHROPIC_API_KEY=sk-ant-...
OUI_DOMAIN=oui.yourdomain.com
OC_DOMAIN=oc.yourdomain.com
# ...

# Hybrid: URL of your remote GPU server
REMOTE_GPU_HOST=https://gpu.yourdomain.com
```

### 2c – Switch to the hybrid LiteLLM config

In `docker-compose.yml`, update the litellm volume mount:

```yaml
litellm:
  volumes:
    - ./litellm-config.hybrid.yaml:/app/config.yaml:ro   # ← change this line
```

Restart LiteLLM:

```bash
docker compose restart litellm
```

### 2d – Verify models appear in Open WebUI

Open `https://oui.yourdomain.com` → model picker. You should see both cloud models (Claude, GPT, Gemini) and remote local models (`llama3.2:3b`, `gpt-oss-20b`).

---

## Adding more remote models

**On the GPU server:** pull the Ollama model or add a new llamacpp instance.

**In `litellm-config.hybrid.yaml` on AWS:** add an entry:

```yaml
- model_name: mistral
  litellm_params:
    model: ollama/mistral
    api_base: "${REMOTE_GPU_HOST}/ollama"
```

Then: `docker compose restart litellm`

---

## Cost reference

| Side | Instance | Cost |
|------|----------|------|
| AWS | `t3.small` (2 vCPU, 2 GB) | ~$15/month |
| GPU server | Hetzner GX2 (A30 GPU) | ~$160/month |
| GPU server | vast.ai on-demand | pay-per-hour |
| GPU server | Your own hardware | electricity only |

---

## Troubleshooting

**Remote models show errors in Open WebUI**
→ Check `REMOTE_GPU_HOST` is set correctly in `.env`
→ Verify the GPU server nginx is running: `curl https://gpu.yourdomain.com/ollama/api/tags`

**LiteLLM can't reach the GPU server**
→ The AWS security group doesn't need special rules — outbound HTTPS (443) is allowed by default
→ Check the GPU server firewall allows inbound 443

**High latency on local model responses**
→ Expected — requests travel AWS → GPU server → back. For latency-sensitive workloads consider the Custom Server setup instead.
