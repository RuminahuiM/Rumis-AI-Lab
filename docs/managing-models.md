# Managing Models

This guide covers how to add, change, and remove models served by llama.cpp and Ollama.

---

## Ollama Models

Ollama models are the simplest to manage. You can pull them from within Open WebUI or from the command line.

**Pull a model:**
```bash
docker exec ollama ollama pull mistral
docker exec ollama ollama pull codellama
docker exec ollama ollama pull gemma2:9b
```

**List installed models:**
```bash
docker exec ollama ollama list
```

**Remove a model:**
```bash
docker exec ollama ollama rm mistral
```

Models appear automatically in Open WebUI after pulling — no configuration changes needed.

---

## llama.cpp Models

### How It Works

Your stack has two components for llama.cpp models:

1. **`llamacpp-init`** — A one-shot container that downloads `.gguf` model files from HuggingFace into a shared Docker volume (`llamacpp_models`).
2. **`llamacpp` service(s)** — Each service runs one llama.cpp server instance, serving one model, on its own port.

To add a model you: (a) add it to the download list, and (b) add a server service for it.

---

### Adding a New Model

#### Step 1: Find the model on HuggingFace

Go to [huggingface.co](https://huggingface.co) and find a GGUF model. You need two things: the **repo name** (e.g. `ggml-org/gpt-oss-20b-GGUF`) and the **filename** of the specific `.gguf` file you want (e.g. `gpt-oss-20b-mxfp4.gguf`).

If you don't specify a filename, the download script will auto-detect the first `.gguf` file in the repo.

#### Step 2: Add to download list

Edit `llamacpp-start.sh` and add an entry to the `MODELS` array:

```bash
MODELS=(
  "ggml-org/gpt-oss-20b-GGUF|gpt-oss-20b-mxfp4.gguf"
)
```

The format is `"repo|filename"`. To auto-detect the filename, leave it empty: `"ggml-org/gpt-oss-20b-GGUF|"`.

You can have multiple models:

```bash
MODELS=(
  "ggml-org/gpt-oss-20b-GGUF|gpt-oss-20b-mxfp4.gguf"
  "bartowski/glm-4-9b-chat-GGUF|glm-4-9b-chat-Q4_K_M.gguf"
)
```

#### Step 3: Add a server service

In `docker-compose.yml`, duplicate the `llamacpp` service block. Change the **service name**, **container name**, **port**, and **model path**:

```yaml
  llamacpp-gptoss:
    image: ghcr.io/ggml-org/llama.cpp:server-cuda
    container_name: llamacpp-gptoss
    restart: unless-stopped
    ports:
      - "8082:8080"          # ← unique port (8081, 8082, 8083, etc.)
    volumes:
      - llamacpp_models:/models:ro
    environment:
      LLAMA_ARG_MODEL: "/models/gpt-oss-20b-mxfp4.gguf"  # ← must match filename
      LLAMA_ARG_HOST: "0.0.0.0"
      LLAMA_ARG_PORT: "8080"
      LLAMA_ARG_CTX_SIZE: "0"
      LLAMA_ARG_N_GPU_LAYERS: "28"  # ← adjust for your GPU VRAM
      LLAMA_ARG_THREADS: "4"
      LLAMA_ARG_JINJA: "1"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    depends_on:
      llamacpp-init:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8080/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s
    networks:
      - ai-stack
```

#### Step 4: Register in Open WebUI

You have two options:

**Option A: Add via the UI (recommended for live changes)**

Go to Settings → Admin Settings → Connections. Under the OpenAI API section, click the **+** button to add a new connection. Enter:
- URL: `http://llamacpp-gptoss:8080/v1`
- Key: `sk-no-key-needed`

Click the refresh button. No restart needed — the model appears immediately.

**Option B: Add via docker-compose.yml (for persistence across rebuilds)**

Update the Open WebUI environment variables. Each URL and key is separated by a semicolon, and the counts must match:

One llamacpp server + LiteLLM:
```yaml
      OPENAI_API_BASE_URLS: "http://llamacpp:8080/v1;http://litellm:4000/v1"
      OPENAI_API_KEYS: "sk-no-key-needed;sk-no-key-needed"
```

Two llamacpp servers + LiteLLM:
```yaml
      OPENAI_API_BASE_URLS: "http://llamacpp:8080/v1;http://llamacpp-gptoss:8080/v1;http://litellm:4000/v1"
      OPENAI_API_KEYS: "sk-no-key-needed;sk-no-key-needed;sk-no-key-needed"
```

Three llamacpp servers + LiteLLM:
```yaml
      OPENAI_API_BASE_URLS: "http://llamacpp:8080/v1;http://llamacpp-gptoss:8080/v1;http://llamacpp-glm5:8080/v1;http://litellm:4000/v1"
      OPENAI_API_KEYS: "sk-no-key-needed;sk-no-key-needed;sk-no-key-needed;sk-no-key-needed"
```

This requires `docker compose restart open-webui` to take effect.

#### Step 5: Deploy

**Full deploy (when starting fresh):**
```bash
docker compose down
docker compose up -d
```

**Adding a model while the stack is already running:**
```bash
docker compose up -d llamacpp-init llamacpp-gptoss
```

This only starts the new services — everything else keeps running. Watch the download with `docker logs -f llamacpp-init`, then verify the server with `docker logs -f llamacpp-gptoss`. Then add the connection in Open WebUI's admin panel (Option A above) and refresh.

You can rename the model in Open WebUI under Settings → Admin Settings → Models.

---

### Removing a Model

#### Step 1: Remove the server service

Delete or comment out the service block in `docker-compose.yml`.

#### Step 2: Remove from Open WebUI

Remove the corresponding URL from `OPENAI_API_BASE_URLS` and its matching key from `OPENAI_API_KEYS`. Or remove it from the Connections page in the admin panel.

#### Step 3: Remove from download list

Remove the entry from the `MODELS` array in `llamacpp-start.sh`.

#### Step 4: Clean up the model file

List models in the volume:
```bash
docker run --rm -v openwebui-stack_llamacpp_models:/models alpine ls -lh /models/
```

Delete a specific model:
```bash
docker run --rm -v openwebui-stack_llamacpp_models:/models alpine rm /models/gpt-oss-20b-mxfp4.gguf
```

Or to delete ALL models and start fresh:
```bash
docker compose down
docker volume rm openwebui-stack_llamacpp_models
docker compose up -d
```

Note: if you delete all models, the init container will re-download any models still listed in the `MODELS` array on next startup.

---

### Changing a Model

To swap one model for another on the same service, update the filename in both `llamacpp-start.sh` (MODELS array) and `docker-compose.yml` (LLAMA_ARG_MODEL), then redeploy.

---

### Temporarily Stopping Services to Free VRAM

Since llama.cpp keeps models loaded in VRAM, you may need to stop other services before running a large model. Use `docker compose stop` (not `down`) to pause services without removing them:

```bash
# Stop specific services to free VRAM
docker compose stop llamacpp llamacpp-glm5

# Start your large model
docker compose up -d llamacpp-large

# When done, bring the others back
docker compose start llamacpp llamacpp-glm5
```

The difference between `stop` and `down`: `stop` pauses containers in place (instant restart later with `start`), while `down` removes them entirely (requires `up -d` to recreate).

You can also stop Ollama if you need maximum VRAM:

```bash
docker compose stop ollama llamacpp
docker compose up -d llamacpp-large
# Later:
docker compose start ollama llamacpp
```

Open WebUI stays running throughout — it will show connection errors for stopped models, but works fine again once you bring them back.

---

### Renaming Models in Open WebUI

Model filenames can be long and ugly in the UI. To rename them, go to Settings → Admin Settings → Models, find the model, click it, and set a custom display name.

---

## Example: Adding gpt-oss-20b

**`llamacpp-start.sh`** — MODELS array:
```bash
MODELS=(
  "ggml-org/gpt-oss-20b-GGUF|gpt-oss-20b-mxfp4.gguf"
)
```

**`docker-compose.yml`** — server service:
```yaml
  llamacpp:
    image: ghcr.io/ggml-org/llama.cpp:server-cuda
    container_name: llamacpp
    restart: unless-stopped
    ports:
      - "8081:8080"
    volumes:
      - llamacpp_models:/models:ro
    environment:
      LLAMA_ARG_MODEL: "/models/gpt-oss-20b-mxfp4.gguf"
      LLAMA_ARG_HOST: "0.0.0.0"
      LLAMA_ARG_PORT: "8080"
      LLAMA_ARG_CTX_SIZE: "0"
      LLAMA_ARG_N_GPU_LAYERS: "28"
      LLAMA_ARG_THREADS: "4"
      LLAMA_ARG_JINJA: "1"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    depends_on:
      llamacpp-init:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8080/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s
    networks:
      - ai-stack
```

Deploy:
```bash
docker compose down
docker volume rm openwebui-stack_llamacpp_models
docker compose up -d
docker logs -f llamacpp-init
```