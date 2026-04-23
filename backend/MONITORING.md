# Monitoring — VLLM Backend

Prometheus + Grafana + DCGM Exporter running alongside VLLM on the DGX Spark.

## Access

| Service    | URL                             | Notes                      |
|------------|----------------------------------|----------------------------|
| Grafana    | `http://<dgx-ip>:3000`          | Anonymous viewer by default |
| Prometheus | `http://<dgx-ip>:9090`          | Raw metrics / query UI      |

Open the **vLLM** folder in Grafana to see the pre-provisioned dashboard.

## Starting the stack

```bash
cd backend
docker compose up -d
```

All four services (vllm, prometheus, grafana, dcgm-exporter) start together.

## Capacity metrics to watch

### Throughput
- **`vllm:e2e_request_latency_seconds`** — end-to-end latency per request
- **`vllm:request_success_total`** — completed requests/s (rate over 1m)
- **`vllm:num_requests_running`** — requests currently being processed
- **`vllm:num_requests_waiting`** — queue depth; sustained >0 means GPU is saturated

### GPU utilization
- **`DCGM_FI_DEV_GPU_UTIL`** — GPU compute utilization %
- **`DCGM_FI_DEV_MEM_COPY_UTIL`** — GPU memory bandwidth utilization %
- **`DCGM_FI_DEV_FB_USED`** — GPU framebuffer (VRAM) used in MiB
- **`DCGM_FI_DEV_FB_FREE`** — GPU framebuffer free in MiB

### KV-cache pressure (token capacity)
- **`vllm:gpu_cache_usage_perc`** — fraction of KV-cache slots in use (0–1)
- **`vllm:cpu_cache_usage_perc`** — CPU KV-cache overflow (should be ~0)

When `gpu_cache_usage_perc` is consistently above ~0.85, you are near token capacity. Options:
- Lower `VLLM_MAX_MODEL_LEN` to fit more concurrent requests
- Lower `VLLM_GPU_MEMORY_UTILIZATION` if you see OOM errors
- Reduce concurrent users / add request queuing

### Concurrency rule of thumb

VLLM processes requests in continuous batching mode. A rough indicator of max concurrent users:

```
max_concurrent ≈ (gpu_memory_utilization × VRAM_total - model_weights) / avg_kv_cache_per_request
```

In practice, watch `num_requests_waiting`: if it is consistently > 0, you have more demand than GPU can serve. The dashboard shows this as a queue depth graph.

## Troubleshooting

**Grafana shows "No data"**
Check Prometheus is scraping: `http://<dgx-ip>:9090/targets` — both `vllm` and `dcgm` should be `UP`.

**VLLM target is DOWN in Prometheus**
VLLM exposes metrics only after the first request. Send a test request and wait ~10s.

**DCGM target is DOWN**
```bash
docker compose logs dcgm-exporter
```
DCGM requires the NVIDIA driver and `SYS_ADMIN` capability. Verify with:
```bash
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
```

**Grafana dashboard missing**
Dashboard is auto-provisioned from `monitoring/grafana/provisioning/dashboards/vllm.json`. If missing, restart Grafana:
```bash
docker compose restart grafana
```
