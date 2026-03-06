# AI Suite Stack

A self-contained Docker Compose stack that combines multiple open-source AI tools into a unified suite: **Open WebUI** for chat, **OpenClaw** for autonomous AI agents, powered by **Ollama**, **llama.cpp**, and cloud APIs (Anthropic Claude, OpenAI GPT, Google Gemini) via **LiteLLM** proxy.

One command to start. All tools share the same model backends.

## What's Included

| Service | Purpose | Port |
|---|---|---|
| **Open WebUI** | Chat interface for all models | `localhost:3000` |
| **OpenClaw** | Autonomous AI agent (tasks, files, APIs) | `localhost:18789` |
| **Ollama** | Local model hosting (Llama, Mistral, Gemma, etc.) | `localhost:11434` |
| **llama.cpp** | GGUF model server with CUDA GPU support | `localhost:8081` |
| **LiteLLM** | Cloud API proxy (Claude, GPT, Gemini → OpenAI-compatible) | `localhost:4000` |

## Prerequisites

- **Docker Desktop** with WSL2 backend (Windows) or Docker Engine (Linux)
- **NVIDIA GPU** with drivers installed (optional but recommended)
- **Anthropic API key** from [console.anthropic.com](https://console.anthropic.com/settings/keys)
- **HuggingFace token** (free) from [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens)

## Quick Start

### 1. Clone and configure

```bash
git clone <your-repo-url>
cd OpenWebui-Stack
```

Edit `.env` and add your API keys:

```env
ANTHROPIC_API_KEY=sk-ant-your-key-here
HF_TOKEN=hf_your-token-here
```

### 2. Add a model for llama.cpp (optional)

Edit `llamacpp-start.sh` and add your model to the `MODELS` array:

```bash
MODELS=(
  "ggml-org/gpt-oss-20b-GGUF|gpt-oss-20b-mxfp4.gguf"
)
```

Then set the matching filename in `docker-compose.yml` under the `llamacpp` service:

```yaml
LLAMA_ARG_MODEL: "/models/gpt-oss-20b-mxfp4.gguf"
```

If you don't want to use llama.cpp yet, comment out the `llamacpp` and `llamacpp-init` services in `docker-compose.yml`.

### 3. Start the stack

```bash
docker compose up -d
```

First run pulls images and downloads models — this takes a while. Subsequent starts are fast.

### 4. Open the UI

Go to **http://localhost:3000** and create your admin account. The first user to sign up becomes the administrator.

All available models appear in the model dropdown. Ollama models show up automatically. llama.cpp and Claude models appear after refreshing connections in Settings → Admin Settings → Connections.

### 5. Set up OpenClaw (one-time)

OpenClaw requires a one-time interactive onboarding:

```bash
mkdir -p openclaw/config openclaw/workspace
docker compose up -d openclaw-gateway
docker compose run --rm openclaw-cli onboard
```

During onboarding, connect to LiteLLM (`http://litellm:4000/v1`) as your model provider — this gives OpenClaw access to all cloud models without needing any API keys directly. See [OpenClaw Setup](docs/openclaw-setup.md) for the full guide.

Get your dashboard URL: `docker compose run --rm openclaw-cli dashboard --no-open`

## Project Structure

```
AI-Suite/
├── docker-compose.yml      # Stack definition
├── .env                    # API keys and secrets (not committed)
├── litellm-config.yaml     # Cloud model definitions
├── llamacpp-start.sh       # Model downloader script
├── openclaw/
│   ├── config/             # OpenClaw agent config & memory
│   └── workspace/          # OpenClaw agent working directory
└── docs/
    ├── managing-models.md      # Adding, removing, swapping llama.cpp/Ollama models
    ├── managing-api-models.md  # Configure cloud providers (Claude, GPT, Gemini)
    ├── openclaw-setup.md       # OpenClaw agent setup and usage
    ├── gpu-configuration.md    # GPU setup and VRAM tuning
    ├── architecture.md         # How the services connect
    └── troubleshooting.md      # Common issues and fixes
```

## Common Operations

**Pull a new Ollama model:**
```bash
docker exec ollama ollama pull mistral
```

**Check service status:**
```bash
docker compose ps
```

**View logs for a service:**
```bash
docker logs -f llamacpp
```

**Stop the stack (preserves all data):**
```bash
docker compose down
```

**Full reset (deletes all data, chat history, models):**
```bash
docker compose down -v
```

## Documentation

- [Managing Models](docs/managing-models.md) — Add, remove, and swap llama.cpp and Ollama models
- [Managing API Models](docs/managing-api-models.md) — Configure Anthropic, OpenAI, Gemini and other cloud providers
- [OpenClaw Setup](docs/openclaw-setup.md) — Personal AI agent setup, security, and usage
- [GPU Configuration](docs/gpu-configuration.md) — NVIDIA setup, VRAM tuning, multi-GPU
- [Architecture](docs/architecture.md) — How services connect, networking, data flow
- [Troubleshooting](docs/troubleshooting.md) — Common issues and solutions

## Data Persistence

All data is stored in Docker volumes and survives `docker compose down`:

- **openwebui_data** — User accounts, chat history, settings
- **ollama_data** — Downloaded Ollama models
- **llamacpp_models** — Downloaded GGUF model files

Only `docker compose down -v` deletes volumes. Don't use `-v` unless you want a full reset.

## Deploying to a Server

This stack is fully portable. Copy the folder to your server, adjust `LLAMA_ARG_N_GPU_LAYERS` and `LLAMA_ARG_THREADS` for your hardware, and run `docker compose up -d`.

See [GPU Configuration](docs/gpu-configuration.md) for server-specific tuning guidelines.