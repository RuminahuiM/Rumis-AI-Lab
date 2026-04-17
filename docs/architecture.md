# Architecture

Rumis AI Lab uses a two-tier architecture: a **frontend VM** for user-facing services (accessed via Azure Application Proxy) and a **backend DGX Spark** for local model inference.

---

## Network Topology

```
Internet → Azure AD → Azure Application Proxy
                          │
                          ▼ (via App Proxy Connector on VM)
                  ┌─────────────────────────────┐
                  │  Linux VM (vSphere)          │
                  │                              │
                  │  Open WebUI :3000             │
                  │    └── OIDC → Azure AD       │        ┌──────────────┐
                  │    └── data → /mnt/openwebui │        │ DGX Spark    │
                  │                              │        │              │
                  │  n8n :5678                    │        │ VLLM :8000   │
                  │    └── OIDC → Azure AD       │        │ (gemma-4     │
                  │    └── data → /mnt/n8n       │        │  26b-a4b)    │
                  │                              │  HTTP  │              │
                  │  LiteLLM :4000 ──────────────┼───────>│              │
                  │    (stateless, config only)   │        └──────────────┘
                  │                              │
                  │  /mnt/openwebui ← VMDK #1    │
                  │  /mnt/n8n       ← VMDK #2    │
                  └─────────────────────────────┘
```

---

## Access Layer

Azure Application Proxy handles:
- **TLS termination** — no nginx or certbot needed on the VM
- **Pre-authentication** — users authenticate via Azure AD before reaching the app
- **Reverse proxy** — routes external URLs to internal VM ports

Two Enterprise Applications in Azure AD:
- `oui.contoso.com` → `http://<vm-ip>:3000` (Open WebUI)
- `n8n.contoso.com` → `http://<vm-ip>:5678` (n8n)

Both use the same Connector Group with a connector installed on the VM.

---

## Services

### Open WebUI (port 3000)

Chat interface for all models. Uses SQLite for its database (stored on `/mnt/openwebui` VMDK). SSO via native OIDC integration with Azure AD.

### LiteLLM (port 4000)

Stateless proxy that routes requests to cloud APIs (Anthropic, OpenAI, Gemini) and the VLLM backend. Config in `litellm-config.yaml`, API keys via `.env`. No persistent storage needed.

### n8n (port 5678)

Workflow automation with MCP Server Trigger for AI tool integration. Uses SQLite (stored on `/mnt/n8n` VMDK). SSO via n8n-oidc community module with Azure AD.

### VLLM (port 8000, DGX Spark)

Serves one model at a time with maximum GPU utilization. Default: Gemma 4 26B-A4B-IT with NVIDIA FP4 quantization. Runs independently on the DGX Spark.

---

## Data Flow

### Chat request (cloud model)
1. User → Azure App Proxy → Open WebUI
2. Open WebUI → LiteLLM → Anthropic/OpenAI/Gemini API

### Chat request (local VLLM model)
1. User → Azure App Proxy → Open WebUI
2. Open WebUI → LiteLLM → VLLM on DGX Spark (:8000)

### n8n MCP tool call
1. LLM decides to call a tool during chat
2. Open WebUI → n8n MCP endpoint (`http://n8n:5678/mcp`)
3. n8n executes the workflow → result returned to conversation

---

## Storage

Each service gets a dedicated VMDK attached to the VM, formatted as ext4:

| Mount Point | Disk | Contents |
|---|---|---|
| `/mnt/openwebui` | VMDK #1 (sdb) | SQLite DB, uploaded files, documents |
| `/mnt/n8n` | VMDK #2 (sdc) | SQLite DB, workflow data, encryption key |

VMDKs live on the vSphere datastore (NetApp-backed). Backed up via vSphere snapshots. The VM itself can be destroyed and re-created — just re-attach the data disks.

---

## Provisioning

1. **Packer** builds a VM template with Docker and open-vm-tools
2. **Terraform** clones the template, attaches two data VMDKs, injects cloud-init
3. **Cloud-init** on first boot: formats/mounts disks, clones repo, writes `.env`, starts services
4. **Azure App Proxy** configured separately in Azure AD portal (see [SSO Setup](sso-setup.md))
