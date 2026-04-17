# Rumis AI Lab

A two-tier AI platform: **frontend VM** (Open WebUI, n8n, LiteLLM) on vSphere with Azure Application Proxy for access and SSO, and **backend** (VLLM) on an NVIDIA DGX Spark.

---

## Architecture

```
Azure AD
    │
    ▼
Azure Application Proxy
    ├── oui.contoso.com ──┐
    └── n8n.contoso.com ──┤
                          │ HTTPS (connector)
                          ▼
                  ┌─────────────────────────────┐
                  │  Linux VM (vSphere)          │
                  │                              │
                  │  Open WebUI :3000             │
                  │    └── OIDC → Azure AD       │        ┌──────────────┐
                  │    └── data → /mnt/openwebui │        │ DGX Spark    │
                  │                              │        │              │
                  │  n8n :5678                    │        │ VLLM :8000   │
                  │    └── OIDC → Azure AD       │        │ (gemma-4-27b │
                  │    └── data → /mnt/n8n       │        │  NVFP4)      │
                  │                              │  HTTP  │              │
                  │  LiteLLM :4000 ──────────────┼───────>│              │
                  │    (stateless)               │        └──────────────┘
                  │                              │
                  │  /mnt/openwebui ← VMDK #1    │
                  │  /mnt/n8n       ← VMDK #2    │
                  └─────────────────────────────┘
```

| Service | Purpose | Port |
|---|---|---|
| **Open WebUI** | Chat interface for all models | `3000` |
| **LiteLLM** | Unified proxy — cloud APIs + VLLM backend | `4000` |
| **n8n** | Workflow automation with MCP tool integration | `5678` |
| **VLLM** | Local model inference on DGX Spark | `8000` |

---

## Quick Start

### 1. Backend (DGX Spark)

```bash
ssh user@dgx-spark
git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git
cd Rumis-AI-Lab/backend
cp .env.example .env && nano .env      # set HF_TOKEN
docker compose up -d
```

See [Backend Setup](docs/backend-setup.md).

### 2. Frontend VM (IaC)

```bash
cd packer
cp variables.pkrvars.hcl.example variables.pkrvars.hcl && nano variables.pkrvars.hcl
packer init . && packer build -var-file=variables.pkrvars.hcl .

cd ../terraform
cp terraform.tfvars.example terraform.tfvars && nano terraform.tfvars
terraform init && terraform apply
```

See [Frontend Setup](docs/frontend-setup.md).

### 3. Frontend VM (Manual)

```bash
git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git
cd Rumis-AI-Lab
cp .env.example .env && nano .env
docker compose up -d
```

### 4. Azure App Proxy + SSO

See [SSO Setup](docs/sso-setup.md) for Azure AD App Registration and Application Proxy configuration.

---

## Data Persistence

Each service gets a dedicated VMDK on the vSphere datastore (NetApp-backed), mounted into the VM:

| Mount | Contents | Backed up via |
|---|---|---|
| `/mnt/openwebui` | SQLite DB, uploaded files | vSphere snapshots |
| `/mnt/n8n` | SQLite DB, workflow data, encryption key | vSphere snapshots |

The VM can be re-provisioned without losing data — just re-attach the VMDKs.

---

## Project Structure

```
Rumis-AI-Lab/
├── docker-compose.yml            # Frontend stack (3 services)
├── litellm-config.yaml           # Cloud + VLLM model routing
├── .env.example                  # All environment variables
│
├── backend/
│   ├── docker-compose.yml        # VLLM on DGX Spark
│   ├── models.yaml               # Tested model configurations
│   ├── .env.example              # Backend environment variables
│   ├── vllm.service              # Systemd auto-start unit
│   └── scripts/setup-dgx.sh     # One-time DGX setup
│
├── packer/
│   ├── ubuntu-vsphere.pkr.hcl   # VM template builder
│   ├── http/                     # Autoinstall config
│   ├── scripts/setup.sh          # Provisioner
│   └── variables.pkrvars.hcl.example
│
├── terraform/
│   ├── main.tf                   # VM deployment + data disks
│   ├── variables.tf              # All parameters
│   ├── outputs.tf                # VM IP, internal URLs
│   ├── templates/cloud-init.yaml # First-boot automation
│   └── terraform.tfvars.example
│
└── docs/
    ├── architecture.md           # Service networking and data flow
    ├── sso-setup.md              # Azure AD + App Proxy + SSO
    ├── frontend-setup.md         # VM deployment (IaC + manual)
    ├── backend-setup.md          # DGX Spark VLLM setup
    ├── managing-api-models.md    # Cloud + VLLM model configuration
    ├── n8n-mcp-setup.md          # n8n as MCP tool server
    └── troubleshooting.md        # Common issues and fixes
```

---

## Documentation

| Guide | What it covers |
|---|---|
| [Architecture](docs/architecture.md) | Two-tier design, networking, data flow |
| [SSO Setup](docs/sso-setup.md) | Azure AD App Registration, App Proxy, OIDC config |
| [Frontend Setup](docs/frontend-setup.md) | Packer + Terraform IaC or manual deploy |
| [Backend Setup](docs/backend-setup.md) | DGX Spark VLLM, model switching |
| [Managing API Models](docs/managing-api-models.md) | Cloud providers + VLLM via LiteLLM |
| [n8n MCP Setup](docs/n8n-mcp-setup.md) | Expose n8n workflows as AI tools |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and fixes |
