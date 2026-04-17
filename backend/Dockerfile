# Extend the official vLLM image with the latest Transformers from source.
# Required because the gemma4 model architecture (Gemma 4) is newer than
# the Transformers version bundled in vllm/vllm-openai:latest.
#
# Rebuild after changing this file:
#   docker compose up -d --build
FROM vllm/vllm-openai:latest

RUN pip install --upgrade --no-cache-dir \
    git+https://github.com/huggingface/transformers.git
