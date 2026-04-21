# VM Setup Guide (Manual – Already-Initialized Ubuntu Server)

Use this guide when you have an already-provisioned Ubuntu 24.04 VM and want to
install Docker and deploy the frontend stack from scratch.

---

## 1. Recover from a Broken Docker Install (SSH Unreachable)

If Docker's install script caused your SSH session to drop, the VM is most
likely still alive — Docker's `apt-get` phase silently reloads `iptables` and
occasionally drops the active SSH connection.

**Step 1 — Open the vSphere Web Console**

1. Log in to the vCenter web UI.
2. Navigate to your VM → **Summary** tab → **Launch Web Console**.
3. Log in with `ailab-adm` credentials.

**Step 2 — Check whether the install is still running**

```bash
ps aux | grep apt
```

If you see `apt-get install docker-ce …` still in the list, wait — the install
is progressing in the background. It can take 3–5 minutes on the first run.

If the process is gone, check the result:

```bash
docker version
```

If Docker is already installed and shows a version, skip straight to
[Section 3](#3-prepare-data-disks).

**Step 3 — Clean up a partial install and reinstall**

If the install failed partway through:

```bash
sudo apt-get remove -y docker-ce docker-ce-cli containerd.io \
  docker-compose-plugin docker-ce-rootless-extras docker-buildx-plugin \
  docker-model-plugin 2>/dev/null || true
sudo apt-get autoremove -y
sudo rm -f /etc/apt/sources.list.d/docker.list \
            /etc/apt/keyrings/docker.asc
sudo apt-get update
```

Then reinstall cleanly (see Section 2).

**Step 4 — Re-enable SSH if it dropped**

```bash
sudo systemctl status ssh
sudo systemctl restart ssh
```

Verify from your workstation:

```bash
ssh ailab-adm@<vm-ip>
```

---

## 2. Install Docker

Run the official install script. Pipe output to `tee` so you can see progress
even if the terminal is slow:

```bash
curl -fsSL https://get.docker.com | sudo sh 2>&1 | tee /tmp/docker-install.log
```

After it finishes, add your user to the `docker` group so you don't need
`sudo` for every command:

```bash
sudo usermod -aG docker $USER
newgrp docker          # apply group change without logging out
```

Verify:

```bash
docker version
docker compose version
```

Both should print version numbers.

---

## 3. Prepare Data Disks

The stack uses two dedicated VMDKs for persistent data so the VM can be
rebuilt without losing anything.

**Identify the disks**

```bash
lsblk
```

You should see the two extra disks (e.g. `/dev/sdb` and `/dev/sdc`) in
addition to the OS disk (`/dev/sda`). They will have no partition table yet.

> If you only see `/dev/sda`, the VMDKs are not attached. Attach them in
> vCenter (VM → Edit Settings → Add Hard Disk) and refresh with
> `sudo partprobe`.

**Format and mount**

```bash
sudo mkfs.ext4 -L openwebui /dev/sdb
sudo mkfs.ext4 -L n8n       /dev/sdc

sudo mkdir -p /mnt/openwebui /mnt/n8n

echo 'LABEL=openwebui /mnt/openwebui ext4 defaults,noatime 0 2' | sudo tee -a /etc/fstab
echo 'LABEL=n8n       /mnt/n8n       ext4 defaults,noatime 0 2' | sudo tee -a /etc/fstab

sudo mount -a
```

Verify:

```bash
df -h /mnt/openwebui /mnt/n8n
```

**Fix ownership** (containers run as uid 1000):

```bash
sudo chown -R 1000:1000 /mnt/openwebui /mnt/n8n
```

> **Re-attaching existing VMDKs?** Skip the `mkfs` step — just add the
> `fstab` entries using `LABEL=` and run `mount -a`. Your data is preserved.

---

## 4. Clone the Repository

```bash
git clone https://github.com/RuminahuiM/Rumis-AI-Lab.git /opt/rumis-ai-lab
cd /opt/rumis-ai-lab
```

---

## 5. Configure Environment Variables

```bash
cp .env.example .env
nano .env
```

Fill in the values relevant to your deployment:

| Variable | Required | Notes |
|---|---|---|
| `VLLM_ENDPOINT` | **Yes** | IP/port of the DGX Spark VLLM service, e.g. `http://192.168.1.200:8000` |
| `ANTHROPIC_API_KEY` | One of these | Get from console.anthropic.com |
| `OPENAI_API_KEY` | One of these | Get from platform.openai.com |
| `GEMINI_API_KEY` | One of these | Get from aistudio.google.com |
| `WEBUI_ADMIN_EMAIL` | **Yes** | First admin account for Open WebUI |
| `WEBUI_ADMIN_PASSWORD` | **Yes** | Must be strong — SSO users will also be created from here |
| `LITELLM_MASTER_KEY` | **Yes** | Change from the default; protects the LiteLLM API |
| `AZURE_TENANT_ID` | For SSO | Your Azure AD tenant GUID |
| `OAUTH_CLIENT_ID` | For SSO | App Registration client ID for Open WebUI |
| `OAUTH_CLIENT_SECRET` | For SSO | App Registration client secret for Open WebUI |
| `OAUTH_CLIENT_ID_N8N` | For SSO | Separate App Registration for n8n |
| `OAUTH_CLIENT_SECRET_N8N` | For SSO | Client secret for n8n App Registration |
| `GENERIC_TIMEZONE` | Optional | Defaults to `Europe/Zurich` |

> **No VLLM backend yet?** Set `VLLM_ENDPOINT=http://127.0.0.1:8000` as a
> placeholder. LiteLLM will still start and serve cloud models — VLLM calls
> will simply error until the backend is reachable.

---

## 6. Start the Stack

```bash
cd /opt/rumis-ai-lab
docker compose up -d
```

Docker will pull the three images on the first run (~1–2 GB total). This takes
3–5 minutes depending on your connection.

---

## 7. Verify

**Check container status**

```bash
docker compose ps
```

Expected output once healthy (may take ~2 min for Open WebUI on first boot):

```
NAME          STATUS
litellm       Up (healthy)
open-webui    Up (healthy)
n8n           Up (healthy)
```

**Check LiteLLM sees your models**

```bash
curl -sf http://localhost:4000/v1/models | python3 -m json.tool
```

**Open the UIs** (before Azure App Proxy is configured)

| Service | URL |
|---|---|
| Open WebUI | `http://<vm-ip>:3000` |
| n8n | `http://<vm-ip>:5678` |
| LiteLLM API | `http://<vm-ip>:4000` (internal only) |

Log in to Open WebUI with the `WEBUI_ADMIN_EMAIL` / `WEBUI_ADMIN_PASSWORD`
you set in `.env`. The first login creates the admin account.

---

## 8. Next Steps

| Task | Guide |
|---|---|
| Configure Azure Application Proxy + SSO | [sso-setup.md](sso-setup.md) |
| Set up DGX Spark VLLM backend | [backend-setup.md](backend-setup.md) |
| Add or remove models | [managing-api-models.md](managing-api-models.md) |
| Connect n8n as MCP tool server | [n8n-mcp-setup.md](n8n-mcp-setup.md) |

---

## Common Operations

```bash
cd /opt/rumis-ai-lab

docker compose ps                              # service status
docker compose logs -f open-webui             # follow Open WebUI logs
docker compose logs -f litellm                # follow LiteLLM logs
docker compose restart litellm                # apply litellm-config.yaml changes
docker compose pull && docker compose up -d   # update all images
docker compose down                           # stop everything (data is safe on VMDKs)
```
