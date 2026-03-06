# GPU Configuration

## Prerequisites

### Windows (Docker Desktop)

1. Install the latest NVIDIA drivers from [nvidia.com/drivers](https://www.nvidia.com/drivers)
2. Docker Desktop must use the WSL2 backend (default on modern installs)
3. Verify GPU access:
   ```bash
   docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
   ```
   You should see your GPU listed.

### Linux (Docker Engine)

1. Install NVIDIA drivers
2. Install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
3. Verify with the same `nvidia-smi` command above

---

## GPU Layers (`LLAMA_ARG_N_GPU_LAYERS`)

This setting controls how many transformer layers are offloaded to GPU. More layers = faster inference but more VRAM. Set to `99` to offload everything that fits.

### RTX 2060 Super (8 GB VRAM)

| Model size | Quantization | Approx. VRAM | Suggested layers |
|---|---|---|---|
| 1-3B | Q4_K_M | ~1-2 GB | 99 (all layers) |
| 7-9B | Q4_K_M | ~4-5 GB | 99 (all layers) |
| 14B | Q4_K_M | ~8 GB | 99 (might just fit) |
| 20B | mxfp4 | ~10 GB | 20-28 (partial) |
| 70B | Q4_K_M | ~40 GB | 5-10 (mostly CPU) |

### 48 GB VRAM (A6000, RTX 6000 Ada, dual 3090)

| Model size | Quantization | Approx. VRAM | Suggested layers |
|---|---|---|---|
| 1-14B | Q4_K_M | ~1-8 GB | 99 (all layers) |
| 20B | Q4_K_M | ~12 GB | 99 (all layers) |
| 70B | Q4_K_M | ~40 GB | 99 (all layers) |
| 70B | Q8_0 | ~70 GB | 50-60 (partial) |
| 120B+ | Q4_K_M | ~65 GB | 40-50 (partial) |

### 96 GB VRAM (dual A6000, H100, 2x RTX 6000 Ada)

| Model size | Quantization | Approx. VRAM | Suggested layers |
|---|---|---|---|
| Up to 70B | Q8_0 | ~70 GB | 99 (all layers, high quality) |
| 70B | FP16 | ~140 GB | 50-60 (partial) |
| 120B | Q4_K_M | ~65 GB | 99 (all layers) |
| 120B | Q8_0 | ~120 GB | 80-90 (mostly GPU) |
| 405B | Q4_K_M | ~220 GB | 30-40 (partial) |

With 48+ GB you can run multiple models simultaneously with full GPU offload. For example, on 48 GB: a 7B + 14B + 20B model all fully on GPU at the same time.

### Tuning Tips

- If you get CUDA out-of-memory errors, lower `LLAMA_ARG_N_GPU_LAYERS`
- Check actual VRAM usage in `docker logs <container>` — look for the "projected to use X MiB" line
- Leave ~500 MB headroom for CUDA overhead
- When running multiple llama.cpp services, they share VRAM permanently (unlike Ollama which loads/unloads dynamically)

---

## Thread Configuration (`LLAMA_ARG_THREADS`)

Controls CPU threads for inference. Only matters for layers running on CPU.

- For fully GPU-offloaded models: `4` is fine (threads are barely used)
- For partially offloaded models: set to number of physical CPU cores minus 2
- For CPU-only: set to number of physical cores

---

## Context Size (`LLAMA_ARG_CTX_SIZE`)

Set to `0` for automatic (uses model default). Larger context uses more VRAM. If you need to save VRAM, set a lower explicit value like `2048` or `4096`.

---

## Disabling GPU

To run CPU-only, remove the `deploy` block from the service in `docker-compose.yml` and set `LLAMA_ARG_N_GPU_LAYERS: "0"`.