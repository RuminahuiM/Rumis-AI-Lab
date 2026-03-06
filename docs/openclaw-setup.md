# OpenClaw Setup

OpenClaw is an open-source personal AI agent that can autonomously execute tasks, manage files, call APIs, and more. It runs as a server and is accessible via a web UI, Telegram, or other messaging platforms.

In this stack, OpenClaw connects to your existing AI backends (Ollama, llama.cpp, Claude, GPT, Gemini) through LiteLLM — without needing any API keys directly.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│  OpenClaw Gateway (:18789)                      │
│  ┌─────────────┐     ┌──────────────────────┐  │
│  │  Agent       │────▶│  LiteLLM (:4000)     │  │
│  │  (autonomous │     │  (Claude, GPT,       │  │
│  │   actions)   │     │   Gemini — no keys   │  │
│  │              │────▶│  needed in OpenClaw)  │  │
│  │              │     └──────────────────────┘  │
│  │              │────▶ Ollama (:11434)          │
│  │              │────▶ llamacpp (:8080)         │
│  └─────────────┘                                │
│  Web UI: http://localhost:18789?token=...       │
└─────────────────────────────────────────────────┘
```

**Security design:** OpenClaw has zero API keys. All cloud model access goes through LiteLLM on the internal Docker network. If the agent is compromised, no keys leak.

---

## Initial Setup (one-time)

### Step 1: Create the data directories

```bash
mkdir -p openclaw/config openclaw/workspace
```

### Step 2: Start the gateway

```bash
docker compose up -d openclaw-gateway
```

Wait until it's healthy:

```bash
docker compose ps openclaw-gateway
```

### Step 3: Run the onboarding wizard

```bash
docker compose run --rm openclaw-cli onboard
```

The wizard will ask you to configure:

- **Agent name** — give your agent a name and personality
- **Model provider** — choose "OpenAI-compatible" and enter:
  - API URL: `http://localhost:4000/v1` (this reaches LiteLLM inside the Docker network)
  - API Key: `sk-no-key-needed`
  - Model: pick any model name from your LiteLLM config (e.g. `claude-opus-4.6`)
- **Ollama** — if prompted, enter `http://localhost:11434` for local models

The onboarding generates a gateway token and writes it to `openclaw/config/openclaw.json`.

### Step 4: Access the Web UI

Get your dashboard URL with the authentication token:

```bash
docker compose run --rm openclaw-cli dashboard --no-open
```

This prints a URL like `http://127.0.0.1:18789/?token=abc123...`. Open it in your browser.

### Step 5: Approve the browser device

If you see "unauthorized" or "pairing required":

```bash
docker compose run --rm openclaw-cli devices list
docker compose run --rm openclaw-cli devices approve <requestId>
```

---

## Connecting to Models

### Cloud models via LiteLLM (recommended)

OpenClaw reaches all cloud models (Claude, GPT, Gemini) through LiteLLM at `http://litellm:4000/v1` on the Docker network. No API keys needed in OpenClaw.

To configure this inside OpenClaw, set up an OpenAI-compatible provider:
- Base URL: `http://litellm:4000/v1`
- API Key: `sk-no-key-needed`
- Available models: all models listed in `litellm-config.yaml`

### Local models via Ollama

OpenClaw can connect directly to Ollama at `http://ollama:11434`. Models you've pulled in Ollama are automatically available.

### Local models via llama.cpp

llama.cpp models are accessible via their OpenAI-compatible API at `http://llamacpp:8080/v1` (or whichever port your llamacpp service uses). API key: `sk-no-key-needed`.

---

## Security Considerations

This setup follows security best practices:

- **No API keys in OpenClaw** — all cloud access goes through LiteLLM as a proxy on the internal network
- **Token-authenticated Web UI** — the dashboard requires a gateway token, not accessible without it
- **Port bound to localhost** — `127.0.0.1:18789` prevents access from other devices on your network
- **Non-root container** — runs as `node` user (uid 1000)
- **CLI hardened** — `cap_drop: [NET_RAW, NET_ADMIN]` and `no-new-privileges`
- **No Docker socket mounted** — the agent cannot access Docker or escape the container
- **Isolated workspace** — agent files are contained in `openclaw/workspace/`

### If deploying on a server (not localhost)

If you expose OpenClaw to the internet:
1. Put it behind a reverse proxy (nginx/Caddy) with HTTPS
2. Never expose port 18789 directly
3. Consider enabling the sandbox feature for agent tool isolation
4. Regularly review what tools and permissions your agent has

---

## Daily Usage

### Start/stop OpenClaw

```bash
# Start
docker compose up -d openclaw-gateway

# Stop (preserves all data)
docker compose stop openclaw-gateway

# Restart
docker compose restart openclaw-gateway
```

### Run CLI commands

The CLI container runs on-demand (it's in the `cli` profile, so it doesn't auto-start):

```bash
# Any openclaw CLI command
docker compose run --rm openclaw-cli <command>

# Examples
docker compose run --rm openclaw-cli config list
docker compose run --rm openclaw-cli devices list
docker compose run --rm openclaw-cli dashboard --no-open
```

### View logs

```bash
docker logs -f openclaw-gateway
```

---

## Data Persistence

All OpenClaw data is stored locally (not in Docker volumes):

| Path | Contents |
|---|---|
| `openclaw/config/` | Agent config, memory, gateway token, API credentials |
| `openclaw/workspace/` | Files the agent creates and works with |

These directories survive `docker compose down`. Back them up if they contain important data.

---

## Updating OpenClaw

```bash
docker compose pull openclaw-gateway
docker compose up -d openclaw-gateway
```

Your config and workspace persist across updates.

---

## Messaging Channels (optional)

OpenClaw supports Telegram, WhatsApp, Discord, Slack, and more. These require interactive setup:

```bash
# Example: set up Telegram
docker compose run --rm openclaw-cli channels add telegram
```

Follow the prompts to create a bot via @BotFather on Telegram and pair it. See the [official OpenClaw docs](https://docs.openclaw.ai/channels) for details on each channel.

---

## Troubleshooting

**"unauthorized" or "disconnected (1008)"**
→ Get a fresh dashboard URL: `docker compose run --rm openclaw-cli dashboard --no-open`

**Agent can't reach models**
→ Check that LiteLLM is running: `docker compose ps litellm`
→ Test from inside the network: `docker exec openclaw-gateway curl -s http://litellm:4000/v1/models`

**Permission errors on config directory**
→ The container runs as uid 1000. Fix ownership: `sudo chown -R 1000:1000 openclaw/`

**Gateway won't start**
→ Check logs: `docker logs openclaw-gateway`
→ Make sure `openclaw/config/` and `openclaw/workspace/` directories exist