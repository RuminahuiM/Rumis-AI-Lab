# Troubleshooting

## Checking Service Status

```bash
docker compose ps
docker compose logs open-webui
docker compose logs litellm
docker compose logs n8n
docker compose logs -f open-webui    # follow in real-time
```

Healthy states: `Up (healthy)` or `Up`. Problem states: `Restarting`, `Up (unhealthy)`, or `Exited`.

---

## Frontend VM Issues

### "Can't reach port 3000 / 5678"

**Service still starting.** Open WebUI downloads embedding models on first launch (~2 min). Check `docker compose logs -f open-webui`.

**Firewall.** Ensure ports 3000 and 5678 are open on the VM for the App Proxy connector.

### "Models not showing in Open WebUI"

**LiteLLM not healthy.** Check `docker compose logs litellm`. Verify API keys in `.env`.

**VLLM backend unreachable.** Test from the VM:
```bash
curl -sf http://<dgx-ip>:8000/v1/models
```

**VLLM calls return 404 `{"detail":"Not Found"}`.** `VLLM_ENDPOINT` is missing the trailing `/v1/`. LiteLLM uses the OpenAI Python client which does RFC-3986 URL joining — without the trailing slash, `/v1` gets replaced by `chat/completions` and VLLM 404s. Correct format: `VLLM_ENDPOINT=http://<dgx-ip>:8000/v1/`

**Refresh connections.** Open WebUI → Settings → Admin Settings → Connections → refresh.

### "Data disk not mounted"

```bash
lsblk                                     # verify disks are attached
mount | grep mnt                           # verify mounts
sudo mount -a                              # retry mounting from fstab
```

If disk is unformatted:
```bash
sudo mkfs.ext4 /dev/sdb
sudo mount /dev/sdb /mnt/openwebui
```

### "Permission denied" on mounted disk

The containers run as uid 1000. Fix ownership:
```bash
sudo chown -R 1000:1000 /mnt/openwebui
sudo chown -R 1000:1000 /mnt/n8n
```

---

## Azure App Proxy Issues

### "This corporate app can't be accessed" (403)

User is not assigned to the Enterprise Application. Go to Azure Portal → Enterprise Applications → Users and groups → Add.

### 502 Bad Gateway

The App Proxy connector can't reach the backend service. Check:
```bash
docker compose ps                          # is the service running?
curl http://localhost:3000                  # can you reach it locally?
```

Also verify the connector service is running: check Azure Portal → Application Proxy → Connectors.

### Connector shows offline

- Verify outbound HTTPS (443) to `*.msappproxy.net` is not blocked
- Restart the connector service
- Check connector logs

---

## SSO Issues

### "AADSTS50011: redirect URI does not match"

The redirect URI in the Azure AD App Registration must exactly match what the app sends:
- OpenWebUI: `https://oui.yourdomain.com/oauth/oidc/callback`
- n8n: check n8n-oidc docs for the exact callback path

### SSO login button doesn't appear in n8n

Check that the n8n-oidc module loaded:
```bash
docker compose logs n8n | grep -i oidc
```

Verify env vars are set: `EXTERNAL_MODULES`, `N8N_OIDC_CLIENT_ID`, `N8N_OIDC_ISSUER`.

### User logs in via SSO but has no permissions

- **OpenWebUI:** The first SSO user may not be admin. Create the admin account first via `WEBUI_ADMIN_EMAIL`/`WEBUI_ADMIN_PASSWORD`, then SSO users get regular access.
- **n8n:** Check n8n-oidc docs for role mapping configuration.

---

## Backend (DGX Spark) Issues

### VLLM won't start

```bash
cd backend && docker compose logs vllm
```

Common causes:
- Missing `HF_TOKEN` for gated models (Gemma)
- NVIDIA runtime not configured: `docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi`

### CUDA out of memory

Lower in `backend/.env`:
```env
VLLM_GPU_MEMORY_UTILIZATION=0.80
VLLM_MAX_MODEL_LEN=4096
```

---

## Useful Commands

```bash
docker compose restart open-webui
docker compose up -d --force-recreate litellm
curl -sf http://localhost:4000/v1/models | python3 -m json.tool
docker compose exec open-webui bash
lsblk                                     # check disk layout
df -h /mnt/openwebui /mnt/n8n             # check disk usage
```
