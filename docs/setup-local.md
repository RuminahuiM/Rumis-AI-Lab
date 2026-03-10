# Local Full Setup (LAN)

Run the full AI suite on your own hardware — accessible from any device on your local network. No cloud services required (though cloud API models are supported too).

**What runs:**
- Open WebUI — chat interface at `http://<lan-ip>:3000`
- OpenClaw — AI agent at `http://<lan-ip>:18789`
- LiteLLM — cloud API proxy (optional, only if you add API keys)
- Ollama — local model hosting
- llama.cpp — GGUF model server (requires NVIDIA GPU)

---

## Prerequisites

- **Docker** (Docker Desktop on Windows/macOS, Docker Engine on Linux)
- **NVIDIA GPU** — required for llama.cpp; recommended for Ollama. CPU-only works but is slow. See [GPU Configuration](gpu-configuration.md).
- At least **16 GB RAM** and **50 GB free disk** for model storage

---

## Step 1 – Clone and configure

```bash
git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git
cd Rumis-AI-Lab
cp .env.example .env
nano .env
```

Fill in what you need. API keys are optional — you can run fully local without them:

```env
# Leave empty if you don't want cloud models
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...

# Required for downloading gated GGUF models from HuggingFace
HF_TOKEN=hf_...
```

---

## Step 2 – Configure llama.cpp model (optional)

By default, llama.cpp downloads `gpt-oss-20b-mxfp4.gguf`. To use a different model, edit `llamacpp-start.sh`:

```bash
MODELS=(
  "your-org/your-model-GGUF|your-model.gguf"
)
```

Then update `LLAMA_ARG_MODEL` in `docker-compose.local.yml` to match the filename.

If you don't want llama.cpp at all, just don't worry — if no GPU is available the llamacpp service will fail to start but everything else will still work.

---

## Step 3 – Create OpenClaw directories

```bash
mkdir -p openclaw/config openclaw/workspace
```

---

## Step 4 – Start the stack

```bash
bash scripts/up-local.sh
```

Or manually:

```bash
docker compose -f docker-compose.local.yml up -d
```

First run pulls all Docker images and downloads models — this takes several minutes (Ollama will pull `llama3.2:3b` in the background). Subsequent starts are fast.

Watch progress:
```bash
docker compose -f docker-compose.local.yml ps
docker logs -f ollama-init     # watch model download
```

---

## Step 5 – Find your LAN IP

```bash
hostname -I | awk '{print $1}'
```

This is the address other devices on your network will use.

---

## Step 6 – Open WebUI first-time setup

Open `http://<lan-ip>:3000` in your browser (or `http://localhost:3000` on the host machine).

1. Create your admin account on the first visit
2. Log in
3. Available models appear in the model picker — Ollama models show up automatically; llama.cpp and cloud models appear after `open-webui` refreshes connections (Settings → Admin Settings → Connections)

> **Accessing from your phone or another device:** use `http://<lan-ip>:3000` — no app needed, it's a web UI.

---

## Step 7 – OpenClaw one-time onboarding

```bash
docker compose -f docker-compose.local.yml run --rm --profile cli openclaw-cli onboard
```

During the wizard:
- Model provider: `OpenAI-compatible`
- API URL: `http://litellm:4000/v1`
- API Key: `sk-no-key-needed`
- Model: `claude-sonnet-4.6` or `llama3.2:3b` or any model from `litellm-config.local.yaml`

Get your dashboard URL:
```bash
docker compose -f docker-compose.local.yml run --rm --profile cli openclaw-cli dashboard --no-open
```

Open the printed URL in your browser, or replace `127.0.0.1:18789` with `<lan-ip>:18789` to access from another device.

---

## Daily usage

```bash
# Start
bash scripts/up-local.sh

# Stop (data is preserved)
docker compose -f docker-compose.local.yml down

# Restart a single service
docker compose -f docker-compose.local.yml restart open-webui

# Pull a new Ollama model
docker exec ollama ollama pull mistral

# View logs
docker compose -f docker-compose.local.yml logs -f
```

---

## Adding more Ollama models

```bash
docker exec ollama ollama pull <model-name>
```

The model will appear in Open WebUI automatically. To expose it through LiteLLM too (for OpenClaw), add an entry to `litellm-config.local.yaml`:

```yaml
- model_name: mistral
  litellm_params:
    model: ollama/mistral
    api_base: http://ollama:11434
```

Then restart LiteLLM: `docker compose -f docker-compose.local.yml restart litellm`

See [Managing Models](managing-models.md) for the full guide.

---

## Troubleshooting

**Can't reach from phone/other device**
→ Check your LAN IP: `hostname -I | awk '{print $1}'`
→ Make sure no firewall is blocking ports 3000 and 18789 on the host

**llama.cpp fails to start**
→ No NVIDIA GPU or CUDA not installed — skip it. Cloud and Ollama models still work.
→ See [GPU Configuration](gpu-configuration.md)

**Ollama models not showing in Open WebUI**
→ Wait for `ollama-init` to finish: `docker logs ollama-init`
→ Refresh connections in Open WebUI: Settings → Admin Settings → Connections

**OpenClaw shows 502**
→ Onboarding not completed — run the `onboard` command in Step 7
