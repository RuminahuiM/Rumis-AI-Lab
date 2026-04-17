# Frontend Setup

The frontend VM runs Open WebUI, n8n, and LiteLLM. Data is persisted on dedicated VMDKs. Access is via Azure Application Proxy.

---

## Prerequisites

- VMware vCenter (for IaC) or any Ubuntu 24.04 server (for manual)
- VLLM backend running on DGX Spark (see [Backend Setup](backend-setup.md))
- At least one cloud API key (Anthropic, OpenAI, or Gemini)
- Azure AD setup for SSO (see [SSO Setup](sso-setup.md))

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

### Deploy the VM

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars         # fill in vCenter, Azure AD, and VLLM endpoint

terraform init
terraform plan                # review: 1 VM + 2 data disks
terraform apply
```

Terraform creates a VM with two additional VMDKs. Cloud-init will:
1. Format and mount `/mnt/openwebui` (VMDK #1) and `/mnt/n8n` (VMDK #2)
2. Clone the repo to `/opt/rumis-ai-lab`
3. Write `.env` from Terraform variables
4. Start all services with `docker compose up -d`

### After Deployment

Wait ~3 minutes for cloud-init, then verify:

```bash
ssh rumis@<vm-ip>
cd /opt/rumis-ai-lab
docker compose ps              # 3 services should be healthy
```

Then configure Azure Application Proxy (see [SSO Setup](sso-setup.md)).

---

## Option B: Manual Deployment

### Install Dependencies

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

### Prepare Data Disks

If you have two additional disks attached (e.g. `/dev/sdb` and `/dev/sdc`):

```bash
sudo mkfs.ext4 /dev/sdb
sudo mkfs.ext4 /dev/sdc
sudo mkdir -p /mnt/openwebui /mnt/n8n
echo '/dev/sdb /mnt/openwebui ext4 defaults,noatime 0 2' | sudo tee -a /etc/fstab
echo '/dev/sdc /mnt/n8n ext4 defaults,noatime 0 2' | sudo tee -a /etc/fstab
sudo mount -a
sudo chown -R 1000:1000 /mnt/openwebui /mnt/n8n
```

### Deploy

```bash
git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git
cd Rumis-AI-Lab
cp .env.example .env
nano .env                      # fill in VLLM_ENDPOINT, Azure AD SSO vars, API keys

docker compose up -d
```

### Verify

```bash
docker compose ps
curl -sf http://localhost:4000/v1/models | python3 -m json.tool
```

Internal access (before Azure App Proxy):
- `http://<vm-ip>:3000` — Open WebUI
- `http://<vm-ip>:5678` — n8n

---

## Common Operations

```bash
docker compose ps
docker compose logs -f open-webui
docker compose restart litellm
docker compose pull && docker compose up -d    # update images
docker compose down                             # stop (data preserved on VMDKs)
```
