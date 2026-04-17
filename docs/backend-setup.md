# Backend Setup (DGX Spark)

The backend runs a single VLLM instance on the NVIDIA DGX Spark, serving one model at a time for maximum GPU utilization.

---

## Prerequisites

- NVIDIA DGX Spark with drivers installed
- NVIDIA Container Toolkit configured for Docker
- HuggingFace token (for gated models like Gemma)

---

## Setup

```bash
# One-time setup (verify NVIDIA, install Docker if needed)
bash backend/scripts/setup-dgx.sh

cd backend
cp .env.example .env
nano .env                      # set HF_TOKEN, review model settings

docker compose up -d
docker compose logs -f vllm    # watch model download progress
```

The first start downloads the model from HuggingFace (~15 GB for Gemma 4 26B-A4B NVFP4). Subsequent starts are fast because the model is cached in the `huggingface_cache` volume.

---

## Default Model

The default configuration serves **Gemma 4 26B-A4B-IT** with NVIDIA FP4 quantization:

```env
VLLM_MODEL=google/gemma-4-26b-a4b-it
VLLM_QUANTIZATION=modelopt_fp4
VLLM_MAX_MODEL_LEN=8192
VLLM_GPU_MEMORY_UTILIZATION=0.90
VLLM_TENSOR_PARALLEL_SIZE=1
```

---

## Switching Models

1. Check `models.yaml` for tested configurations
2. Update `.env` with the new model's settings
3. Restart:
   ```bash
   docker compose down && docker compose up -d
   ```

Only one model runs at a time. Running multiple VLLM instances would partition GPU memory and degrade performance.

---

## Verifying the Backend

```bash
# Health check
curl http://localhost:8000/health

# List available models
curl http://localhost:8000/v1/models

# Test inference
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "google/gemma-4-26b-a4b-it", "messages": [{"role": "user", "content": "Hello"}]}'
```

---

## Auto-start with Systemd

To start VLLM automatically on boot:

```bash
sudo cp vllm.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable vllm
sudo systemctl start vllm
```

---

## Troubleshooting

**Model download hangs or fails:**
- Verify `HF_TOKEN` is set and has access to the model
- Check `docker compose logs vllm` for authentication errors
- The health check has a 300s start period to allow for downloads

**CUDA out of memory:**
- Lower `VLLM_GPU_MEMORY_UTILIZATION` (e.g. `0.80`)
- Reduce `VLLM_MAX_MODEL_LEN` (e.g. `4096`)
- Try a smaller model or more aggressive quantization

**VLLM container keeps restarting:**
- Check logs: `docker compose logs vllm`
- Verify NVIDIA runtime: `docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi`

**`Transformers does not recognize this architecture` error:**
- The model is newer than the Transformers version bundled in the official vLLM image
- Fixed in this repo by extending the image with the latest Transformers (`backend/Dockerfile`)
- If you see this after pulling a new model: `docker compose build --no-cache && docker compose up -d`
