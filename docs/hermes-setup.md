# Hermes Agent Setup

Hermes Agent (by Nous Research) is a Python-based autonomous AI agent with persistent memory, self-learning via GEPA, and multi-agent support. It runs in this stack as an alternative to OpenClaw, with all model access routed through LiteLLM — no API keys needed inside the agent container.

OpenClaw continues running alongside Hermes until you are ready to remove it. Use `hermes claw migrate` to import your data.

---

## Architecture

```
┌────────────────────────────────────────────────────────┐
│  Hermes Gateway (:8642)                                │
│  ┌──────────────┐     ┌──────────────────────────────┐ │
│  │  Agent        │────▶│  LiteLLM (:4000)             │ │
│  │  (autonomous  │     │  (Claude, GPT, Gemini —      │ │
│  │   reasoning,  │     │   no API keys in Hermes)     │ │
│  │   memory,     │     └──────────────────────────────┘ │
│  │   skills)     │────▶ n8n MCP (:5678/mcp)            │
│  └──────────────┘       (Gmail, Slack, GitHub, etc.)   │
│  API: http://hermes-gateway:8642  (internal net only)  │
└────────────────────────────────────────────────────────┘
```

**Security design:** Hermes holds zero API keys. All cloud model access goes through LiteLLM on the internal Docker network. The n8n MCP server handles external credentials (Slack tokens, GitHub PATs, etc.) in its own encrypted store — Hermes never sees them directly.

---

## Prerequisites

1. **DNS** — create an A record for `hermes.<yourdomain>` pointing to your EC2 Elastic IP.
2. **`.env`** — add the three new variables:
   ```bash
   HERMES_DOMAIN=hermes.yourdomain.com
   HERMES_AUTH_USER=admin
   HERMES_AUTH_PASSWORD=choose-a-strong-password
   ```
3. **Re-run `init-ssl.sh`** — issues the Let's Encrypt cert and regenerates the nginx config with the new Hermes subdomain. After it completes, start the full stack:
   ```bash
   bash scripts/init-ssl.sh
   docker compose up -d
   ```

---

## Initial Setup (one-time)

### Step 1: Build the Docker image

```bash
docker compose build hermes-gateway
```

This builds the local `rumis-hermes:latest` image (~300 MB, Python 3.11-slim with hermes-agent installed).

### Step 2: Create the data directory

If the EC2 UserData script already ran this is done automatically. Otherwise:

```bash
mkdir -p hermes/data
sudo chown -R 1001:1001 hermes/data
```

### Step 3: Start the gateway

```bash
docker compose up -d hermes-gateway
docker compose ps hermes-gateway    # wait for (healthy)
```

The health check polls `GET /health` on port 8642 with a 60s start period.

### Step 4: Run the setup wizard

```bash
docker compose run --rm hermes-cli setup
```

The wizard will ask you to confirm:
- **Model provider** — select "OpenAI-compatible". The seed config pre-fills the base URL (`http://litellm:4000/v1`) and API key (`sk-no-key-needed`), so you only need to confirm them.
- **Default model** — pre-filled as `claude-sonnet-4.6`. Must match a `model_name` in `litellm-config.yaml`.
- **Optional integrations** — Telegram, Slack, Discord, etc. Can be skipped and added later via `hermes gateway`.

Configuration is saved to `hermes/data/` and survives container restarts.

### Step 5: Access the agent

Hermes does not bundle a browser UI in the container. Two options:

**Option A — CLI** (always available):
```bash
docker compose run --rm hermes-cli chat
```

**Option B — Hermes Workspace** (community browser UI, see below):
```
https://hermes.<yourdomain>
```

---

## Hermes Workspace (optional browser UI)

[Hermes Workspace](https://github.com/outsourc-e/hermes-workspace) is a community web UI for chat, terminal access, memory browsing, and skill management.

It is **not included in the default compose file** to avoid extra RAM pressure on t3.small. Run it on-demand when you need the UI:

```bash
docker run --rm -p 3002:3000 \
  -e HERMES_API_URL=http://hermes-gateway:8642 \
  --network rumis-ai-lab_frontend-net \
  outsource/hermes-workspace:latest
```

Then open `http://localhost:3002` in your browser (or `https://hermes.<yourdomain>` if nginx is configured and you are running this on the server).

---

## Connecting to Models

Hermes accesses all cloud models through LiteLLM at `http://litellm:4000/v1` on the internal Docker network. This is pre-configured via environment variables in `docker-compose.yml`:

```yaml
OPENAI_BASE_URL: "http://litellm:4000/v1"
OPENAI_API_KEY:  "sk-no-key-needed"
```

Available models are defined in `litellm-config.yaml`. To see the full list:

```bash
docker exec hermes-gateway curl -s http://litellm:4000/v1/models | python3 -m json.tool
```

To change the default model after setup:

```bash
docker compose run --rm hermes-cli model
```

---

## Connecting to n8n Tools (MCP)

The seed config already wires up the n8n MCP endpoint:

```yaml
mcp_servers:
  n8n:
    url: "http://n8n:5678/mcp"
```

This gives Hermes access to any tools you expose via n8n workflows (Gmail, Slack, GitHub, Postgres, HTTP, and 400+ others). See [docs/n8n-mcp-setup.md](n8n-mcp-setup.md) for how to create and expose tools.

---

## Migrating from OpenClaw

Hermes includes a built-in migration command that imports data from OpenClaw:

```bash
# Preview what will be imported (no writes)
docker compose run --rm hermes-cli claw migrate --dry-run

# Import conversations and user data (no secrets)
docker compose run --rm hermes-cli claw migrate --preset user-data

# Full migration (overwrite any conflicts)
docker compose run --rm hermes-cli claw migrate --overwrite
```

OpenClaw continues running throughout — stop it only when you are confident the migration is complete and Hermes is working as expected.

---

## Security Considerations

This setup follows the same security model as OpenClaw:

- **No API keys in the container** — all cloud model access goes through LiteLLM on the internal Docker network
- **Nginx basic auth on `hermes.<domain>`** — username/password (set in `.env` as `HERMES_AUTH_USER`/`HERMES_AUTH_PASSWORD`) required before the request reaches Hermes
- **Segmented Docker networks** — nginx can reach `hermes-gateway` on `frontend-net`; `hermes-gateway` can reach LiteLLM and n8n on `backend-net`; nginx cannot directly reach either
- **Non-root container** — runs as `hermes` user (uid 1001)
- **Port bound to localhost** — `127.0.0.1:8642` prevents direct external access
- **No Docker socket mounted** — the agent cannot escape the container
- **Isolated data directory** — all agent files contained in `hermes/data/`
- **n8n holds external credentials** — third-party API keys (Slack, Gmail, etc.) stay in n8n's encrypted store; Hermes only sees tool results

---

## Daily Usage

```bash
# Start / stop / restart
docker compose up -d hermes-gateway
docker compose stop hermes-gateway
docker compose restart hermes-gateway

# Run any CLI command (one-off)
docker compose run --rm hermes-cli <command>

# Examples
docker compose run --rm hermes-cli chat
docker compose run --rm hermes-cli status
docker compose run --rm hermes-cli model
docker compose run --rm hermes-cli gateway       # configure messaging channels

# View logs
docker logs -f hermes-gateway
```

---

## Data Persistence

All Hermes data is stored in `hermes/data/` (bind-mounted from the host). This survives `docker compose down`.

| Path | Contents |
|---|---|
| `hermes/data/` | Config, memories, sessions, skills, GEPA training data |

Back this directory up before updating or migrating.

---

## Updating Hermes

Hermes is installed from PyPI via `pip install hermes-agent` during the Docker image build. To update:

```bash
docker compose build --no-cache hermes-gateway
docker compose up -d hermes-gateway
```

Your data in `hermes/data/` is unaffected — it lives on the host, not in the image.

---

## Troubleshooting

**Gateway won't start**
```bash
docker logs hermes-gateway
# Fix ownership if needed:
sudo chown -R 1001:1001 hermes/data/
# Re-run setup:
docker compose run --rm hermes-cli setup
```

**Health check failing**
The `/health` endpoint has a 60s `start_period`. If it keeps failing after that:
```bash
# Confirm the gateway port is listening
docker exec hermes-gateway curl -sf http://localhost:8642/health
# If 404, try the root path to confirm the process is up:
docker exec hermes-gateway curl -sf http://localhost:8642/
```

**Agent can't reach models**
```bash
docker exec hermes-gateway curl -s http://litellm:4000/v1/models
# If this fails, check LiteLLM is healthy:
docker compose ps litellm
```

**Permission errors on data directory**
The container runs as uid 1001. Fix ownership:
```bash
sudo chown -R 1001:1001 hermes/data/
```

**`hermes claw migrate` fails**
```bash
# Ensure OpenClaw is running
docker compose ps openclaw-gateway
# Try dry-run first
docker compose run --rm hermes-cli claw migrate --dry-run
```
