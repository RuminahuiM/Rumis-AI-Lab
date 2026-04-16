# Troubleshooting

## Checking Service Status

```bash
# Frontend VM
docker compose ps

# Backend (DGX Spark)
cd backend && docker compose ps

# View logs for a specific service
docker compose logs open-webui
docker compose logs litellm
docker compose logs postgres

# Follow logs in real-time
docker compose logs -f open-webui
```

Healthy states: `Up (healthy)` or `Up`. Problem states: `Restarting`, `Up (unhealthy)`, or `Exited`.

---

## Frontend VM Issues

### "Can't reach localhost:3000"

**Open WebUI is still starting up.** On first launch it downloads embedding models which takes a few minutes. Check progress with `docker compose logs -f open-webui`. Wait for the health check to pass.

**Port conflict.** Another application might be using port 3000. Check with `ss -tlnp | grep 3000`.

### "Models not showing in Open WebUI"

**LiteLLM not healthy.** Check `docker compose ps litellm` and `docker compose logs litellm`. Verify API keys in `.env` are correct.

**VLLM backend unreachable.** Test connectivity from the frontend VM:
```bash
curl -sf http://<dgx-ip>:8000/v1/models
```
If this fails, check the backend (firewall, VLLM status).

**Refresh connections.** In Open WebUI: Settings → Admin Settings → Connections → click the refresh button.

### "LiteLLM unhealthy / API errors"

Check logs:
```bash
docker compose logs litellm
```

Common causes:
- Invalid API key in `.env` — verify and restart: `docker compose restart litellm`
- `VLLM_ENDPOINT` not set or unreachable — check `.env` and network connectivity
- Config syntax error in `litellm-config.yaml`

### "PostgreSQL connection refused"

```bash
docker compose logs postgres
docker compose exec postgres pg_isready -U rumis
```

If PostgreSQL won't start, check NFS mount:
```bash
mount | grep nfs
docker volume inspect rumis-ai-lab_postgres_data
```

### "NFS mount failed" or volumes won't create

```bash
# Test NFS manually
sudo mount -t nfs4 -o vers=4.1 ${NAS_IP}:${NAS_SHARE_PATH}/postgres /mnt
```

Common causes:
- NFS not enabled on Synology (Control Panel → File Services → NFS)
- Wrong NAS_IP or NAS_SHARE_PATH in `.env`
- Firewall blocking NFS (port 2049)
- NFS permissions not set for this VM's IP (see [Storage Setup](storage-setup.md))

### "Connection refused" between services

Make sure all services are on the same Docker network. Check `docker compose ps` — if a service isn't running, others can't reach it.

### "n8n can't connect to PostgreSQL"

n8n uses a separate database (`n8n`) on the same PostgreSQL instance. If it wasn't created automatically, create it manually:
```bash
docker compose exec postgres createdb -U rumis n8n
docker compose restart n8n
```

---

## Backend (DGX Spark) Issues

### "VLLM won't start / keeps restarting"

```bash
cd backend && docker compose logs vllm
```

Common causes:
- **Missing HF_TOKEN** — required for gated models like Gemma. Set it in `backend/.env`
- **NVIDIA runtime not configured** — verify with: `docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi`
- **Model not found** — check the model ID in `VLLM_MODEL` is correct on HuggingFace

### "CUDA out of memory"

Lower GPU memory usage in `backend/.env`:
```env
VLLM_GPU_MEMORY_UTILIZATION=0.80
VLLM_MAX_MODEL_LEN=4096
```

Then restart: `docker compose down && docker compose up -d`

### "Model download takes forever"

First download can take 10-30 minutes depending on model size and network. The model is cached in the `huggingface_cache` volume — subsequent starts are fast.

Check progress: `docker compose logs -f vllm`

---

## SSL / Nginx Issues

### "init-ssl.sh fails with ACME challenge error"

DNS must resolve to the server's IP before running `init-ssl.sh`:
```bash
nslookup oui.yourdomain.com    # must return this server's IP
nslookup n8n.yourdomain.com    # must return this server's IP
```

Also verify ports 80 and 443 are open (firewall, security group).

### "Certificate renewal failed"

Check certbot logs:
```bash
docker compose logs certbot
```

Certbot renews automatically every 12 hours. If renewal fails, verify the `.well-known/acme-challenge/` path is being served correctly by nginx.

---

## Useful Commands

```bash
# Restart a single service
docker compose restart open-webui

# Force recreate a service (picks up config changes)
docker compose up -d --force-recreate litellm

# Check what LiteLLM exposes
curl -sf http://localhost:4000/v1/models | python3 -m json.tool

# Check VLLM health (from frontend VM)
curl -sf http://<dgx-ip>:8000/health

# Shell into a container for debugging
docker compose exec open-webui bash
docker compose exec postgres psql -U rumis openwebui

# Check network connectivity
docker compose exec open-webui curl -s http://litellm:4000/v1/models
docker compose exec open-webui curl -s http://n8n:5678/healthz

# Check GPU usage (on DGX Spark)
nvidia-smi
```

---

## Full Reset

If nothing else works, start fresh. Data on the NAS is preserved — only the container state is reset:

```bash
docker compose down
docker compose up -d
```

To also reset NAS data (destructive — loses all chat history, workflows, and accounts):

```bash
docker compose down -v
docker compose up -d
```
