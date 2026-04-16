# Frontend Setup

The frontend VM runs Open WebUI, n8n, LiteLLM, PostgreSQL, nginx, and certbot. It can be deployed via IaC (Packer + Terraform) or manually.

---

## Prerequisites

- VMware vCenter (for IaC) or any Ubuntu 24.04 server (for manual)
- DNS: two A records pointing at the VM's IP (`oui.yourdomain.com`, `n8n.yourdomain.com`)
- Synology NAS with NFS configured (see [Storage Setup](storage-setup.md))
- VLLM backend running on DGX Spark (see [Backend Setup](backend-setup.md))
- At least one cloud API key (Anthropic, OpenAI, or Gemini)

---

## Option A: IaC Deployment (Packer + Terraform)

### Build the VM Template (one-time)

```bash
cd packer
cp variables.pkrvars.hcl.example variables.pkrvars.hcl
nano variables.pkrvars.hcl    # fill in vCenter credentials, datastore, network, ISO path

packer init .
packer build -var-file=variables.pkrvars.hcl .
```

This creates a VM template in vCenter with Docker, NFS client, and cloud-init pre-installed.

### Deploy the VM

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars         # fill in vCenter, NAS, domain, and password values

terraform init
terraform plan                # review what will be created
terraform apply               # deploy the VM
```

Terraform outputs the VM IP and SSH command. Cloud-init will:
1. Mount NFS shares from the Synology NAS
2. Clone the repo to `/opt/rumis-ai-lab`
3. Write `.env` from Terraform variables
4. Run `init-ssl.sh` to bootstrap SSL
5. Start all services with `docker compose up -d`

### After Deployment

Wait ~5 minutes for cloud-init to complete, then verify:

```bash
ssh rumis@<vm-ip>
cd /opt/rumis-ai-lab
docker compose ps              # all services should be healthy
```

---

## Option B: Manual Deployment

### Install Dependencies

```bash
# Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# NFS client
sudo apt install -y nfs-common
```

### Deploy

```bash
git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git
cd Rumis-AI-Lab
cp .env.example .env
nano .env                      # fill in ALL values

# Verify DNS resolves to this server before proceeding
nslookup oui.yourdomain.com

bash scripts/init-ssl.sh       # ~2 min: issues SSL certs
docker compose up -d           # ~5 min first run (image pulls)
```

### Verify

```bash
docker compose ps              # all services healthy
curl -sf http://localhost:4000/v1/models | python3 -m json.tool   # LiteLLM models
```

Open your browser:
- `https://oui.yourdomain.com` — Open WebUI (create admin account on first visit)
- `https://n8n.yourdomain.com` — n8n (create admin account on first visit)

---

## n8n Database Setup

n8n uses a separate database (`n8n`) on the same PostgreSQL instance. The database is created automatically by n8n on first start. If you need to create it manually:

```bash
docker exec postgres createdb -U rumis n8n
```

---

## Common Operations

```bash
# Check service status
docker compose ps

# View logs
docker compose logs -f
docker compose logs -f open-webui

# Restart a single service
docker compose restart litellm

# Update images
docker compose pull && docker compose up -d

# Stop (data preserved on NAS)
docker compose down
```
