# Troubleshooting

## Checking Service Status

```bash
# See all services and their status
docker compose ps

# View logs for a specific service
docker logs llamacpp
docker logs open-webui
docker logs litellm
docker logs ollama

# Follow logs in real-time
docker logs -f llamacpp
```

Healthy states: `Up (healthy)` or `Up`. Problem states: `Restarting`, `Up (unhealthy)`, or `Exited`.

---

## Common Issues

### "Can't reach localhost:3000"

**Open WebUI is still starting up.** On first launch it downloads embedding models from HuggingFace which takes a few minutes. Check progress with `docker logs -f open-webui`. Wait for the Open WebUI banner to appear in the logs.

**Port conflict.** Another application might be using port 3000. Change the port mapping in `docker-compose.yml`:
```yaml
    ports:
      - "3001:8080"  # Change 3000 to any free port
```

### "Models not showing in Open WebUI"

**For Ollama models:** Check `docker exec ollama ollama list` — if no models are listed, the download may still be in progress. Check `docker logs ollama-init`.

**For llama.cpp models:** Go to Settings → Admin Settings → Connections and click the refresh button next to the OpenAI connections. If the connection shows an error, check `docker logs llamacpp` — the server might not have started yet.

**For Claude models:** Check `docker logs litellm`. Make sure your `ANTHROPIC_API_KEY` in `.env` is correct. Verify LiteLLM is running: `curl http://localhost:4000/v1/models`.

### "llamacpp keeps restarting"

**Model file not found.** The `LLAMA_ARG_MODEL` path in `docker-compose.yml` must exactly match the filename downloaded by `llamacpp-start.sh`. Check what's in the volume:
```bash
docker run --rm -v openwebui-stack_llamacpp_models:/models alpine ls -lh /models/
```

**Model download failed.** Check `docker logs llamacpp-init` to see if the download completed successfully.

### "CUDA out of memory"

Lower `LLAMA_ARG_N_GPU_LAYERS` in `docker-compose.yml` for the affected service. See [GPU Configuration](gpu-configuration.md) for recommended values.

If running multiple llama.cpp services, stop the ones you're not using:
```bash
docker compose stop llamacpp-other
```

### "no usable GPU found" in llamacpp logs

**Using the wrong image.** Make sure the llamacpp service uses `ghcr.io/ggml-org/llama.cpp:server-cuda`, not the CPU image.

**NVIDIA Container Toolkit not working.** Test with:
```bash
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```
If this fails, your GPU passthrough isn't set up. On Windows, update Docker Desktop and your NVIDIA drivers. On Linux, install the NVIDIA Container Toolkit.

**Missing deploy block.** The service needs the GPU reservation in `docker-compose.yml`:
```yaml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

### "Ollama shows as unhealthy"

This is usually a timing issue — the healthcheck runs before Ollama finishes initializing. The current setup uses `ollama list` for healthchecks which is reliable. If it persists, increase `start_period` in the healthcheck config.

Check if Ollama is actually running:
```bash
docker exec ollama ollama list
```

### "LiteLLM unhealthy / Claude models not working"

Check the API key:
```bash
docker logs litellm
```

Look for authentication errors. If you see them, verify your `ANTHROPIC_API_KEY` in `.env` is correct and has credits.

### "Connection refused" errors between services

Make sure all services are on the same network. Check `docker compose ps` — if a service isn't running, the others can't reach it. This is expected for temporarily stopped services.

---

## Useful Commands

```bash
# Restart a single service
docker compose restart open-webui

# Stop a service without removing it (preserves state)
docker compose stop llamacpp

# Start a stopped service
docker compose start llamacpp

# Force recreate a service (picks up config changes)
docker compose up -d --force-recreate llamacpp

# Check what's using GPU memory
nvidia-smi

# Shell into a container for debugging
docker exec -it llamacpp bash
docker exec -it open-webui bash

# Check network connectivity between services
docker exec open-webui curl -s http://llamacpp:8080/v1/models
docker exec open-webui curl -s http://litellm:4000/v1/models
docker exec open-webui curl -s http://ollama:11434/api/tags
```

---

## Full Reset

If nothing else works, start completely fresh:

```bash
docker compose down -v      # Removes containers AND volumes (all data lost)
docker compose up -d        # Recreate everything from scratch
```

This deletes all chat history, user accounts, and downloaded models.