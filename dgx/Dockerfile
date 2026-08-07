# Extend the official vLLM image with the latest Transformers from source.
# Required because the gemma4 model architecture (Gemma 4) is newer than
# the Transformers version bundled in vllm/vllm-openai:latest.
#
# Rebuild after changing this file:
#   docker compose up -d --build
FROM vllm/vllm-openai:latest

RUN apt-get update && apt-get install -y --no-install-recommends git \
    && pip install --upgrade --no-cache-dir \
       git+https://github.com/huggingface/transformers.git \
    && apt-get purge -y git && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*
