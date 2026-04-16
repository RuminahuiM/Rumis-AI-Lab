# Architecture

Rumis AI Lab uses a two-tier architecture: a **frontend VM** for user-facing services and a **backend DGX Spark** for local model inference. All persistent data is stored on a Synology NAS via NFS.

---

## Network Topology

```
Internet
    │
    ▼
┌───────────────────────────────────────────────┐
│  Frontend VM (vCenter)                        │
│                                               │
│  ┌─────────┐   ┌────────────┐   ┌─────────┐  │
│  │ nginx   │──►│ Open WebUI │──►│ LiteLLM │  │    ┌────────────────┐
│  │ :80/443 │   │ :3000      │   │ :4000   │──┼───►│ DGX Spark      │
│  │         │──►│            │   │         │  │    │                │
│  │         │   └──────┬─────┘   └─────────┘  │    │ VLLM :8000     │
│  │         │──►┌──────┴─────┐                │    │ (gemma-4-27b)  │
│  │         │   │ n8n :5678  │                │    └────────────────┘
│  └─────────┘   └──────┬─────┘                │
│                       │                      │
│                ┌──────┴──────┐               │
│                │ PostgreSQL  │               │    ┌────────────────┐
│                │ :5432       │               │    │ Synology NAS   │
│                └─────────────┘               │    │                │
│                       │                      │    │ NFS exports:   │
│                       └──────────────────────┼───►│ /postgres      │
│                                              │    │ /openwebui     │
│                                              │    │ /n8n           │
└──────────────────────────────────────────────┘    └────────────────┘
```

---

## Docker Networks (Frontend VM)

| Network | Services | Purpose |
|---|---|---|
| `frontend-net` | nginx, open-webui, n8n | Public-facing tier |
| `backend-net` | open-webui, n8n, litellm, postgres | Internal services |

nginx cannot reach PostgreSQL or LiteLLM directly. Open WebUI and n8n bridge both networks.

---

## Services

### Open WebUI (port 3000)

The user-facing web interface. Connects to LiteLLM for all model access and presents them in a unified model picker. Stores user accounts, chat history, and settings in PostgreSQL. Uploaded files and documents are stored in the `openwebui_data` NFS volume.

### LiteLLM (port 4000)

Unified gateway that routes requests to both cloud APIs (Anthropic, OpenAI, Gemini) and the local VLLM backend on the DGX Spark. All model access goes through LiteLLM — neither Open WebUI nor n8n hold cloud API keys directly.

Configuration is in `litellm-config.yaml`. API keys and the VLLM endpoint are passed via `.env`.

### PostgreSQL (port 5432)

Shared database for Open WebUI and n8n. Data is stored on the Synology NAS via NFS, making it survive VM re-provisioning. PostgreSQL handles NFS gracefully with proper fsync and WAL journaling.

### n8n (port 5678)

Visual workflow automation platform that doubles as an **MCP (Model Context Protocol) server**. Using n8n's built-in MCP Server Trigger node, any workflow can be exposed as an AI-callable tool — giving Open WebUI access to 400+ integrations (Gmail, Slack, GitHub, databases, HTTP APIs) without holding any credentials.

All third-party secrets are stored in n8n's encrypted credential store. The AI receives only tool results, never the underlying credentials.

See [n8n MCP Setup](n8n-mcp-setup.md) for instructions.

### VLLM (port 8000, DGX Spark)

Serves a single model at a time with maximum GPU utilization. Default: Gemma 4 27B-IT with NVIDIA FP4 quantization. The OpenAI-compatible API is accessible from the frontend VM via the `VLLM_ENDPOINT` configuration.

Model files are cached in a Docker volume on the DGX Spark so subsequent restarts are fast.

---

## Data Flow

### Chat request (cloud model)
1. User → nginx (HTTPS) → Open WebUI
2. Open WebUI → LiteLLM → Anthropic/OpenAI/Gemini API
3. Response streams back the same path

### Chat request (local VLLM model)
1. User → nginx (HTTPS) → Open WebUI
2. Open WebUI → LiteLLM → VLLM on DGX Spark (:8000)
3. Response streams back the same path

### n8n MCP tool call
1. LLM decides to call a tool during chat
2. Open WebUI → n8n MCP endpoint (`http://n8n:5678/mcp`)
3. n8n executes the workflow (API call, DB query, etc.)
4. Result returned to the conversation

---

## Storage

All Docker volumes use NFS mounts to the Synology NAS:

| Volume | NFS Path | Contents |
|---|---|---|
| `postgres_data` | `/volume1/rumis-ai-lab/postgres` | PostgreSQL databases |
| `openwebui_data` | `/volume1/rumis-ai-lab/openwebui` | Uploaded files, documents |
| `n8n_data` | `/volume1/rumis-ai-lab/n8n` | Workflow data, encryption key |

The frontend VM can be destroyed and re-provisioned without data loss.

---

## Provisioning

The frontend VM is managed as code:

1. **Packer** builds a VM template with Docker, NFS client, and cloud-init pre-installed
2. **Terraform** clones the template, injects cloud-init config via guestinfo, and starts the VM
3. **Cloud-init** on first boot: mounts NFS, clones the repo, writes `.env`, runs `init-ssl.sh`, starts services

The backend (DGX Spark) runs independently with its own `docker-compose.yml`.
