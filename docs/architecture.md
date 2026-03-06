# Architecture

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Network (ai-stack)                │
│                                                             │
│  ┌──────────┐    Ollama API     ┌────────────────────────┐  │
│  │  Ollama   │◄────────────────►│                        │  │
│  │ :11434    │                  │                        │  │
│  └──────────┘                  │     Open WebUI          │  │
│                                │     :3000               │  │
│  ┌──────────┐   OpenAI API     │                        │  │
│  │ llama.cpp │◄────────────────►│                        │  │
│  │ :8081     │   /v1/chat/...  │                        │  │
│  └──────────┘                  │                        │  │
│                                │                        │  │
│  ┌──────────┐   OpenAI API     │                        │  │
│  │ LiteLLM  │◄────────────────►│                        │  │
│  │ :4000    │   /v1/chat/...   │                        │  │
│  └──────────┘                  └────────────────────────┘  │
│       │                                                     │
│       │ Anthropic API                                       │
│       ▼                                                     │
│  api.anthropic.com                                          │
└─────────────────────────────────────────────────────────────┘
```

## Services

### Open WebUI (port 3000)

The user-facing web interface. Connects to all backends and presents them in a unified model picker. Stores user accounts, chat history, and settings in an SQLite database inside the `openwebui_data` volume.

Connects to:
- Ollama via its native API protocol
- llama.cpp and LiteLLM via the OpenAI-compatible API (`/v1/chat/completions`)

### Ollama (port 11434)

Manages and serves local models. Handles model downloading, quantization, and GPU memory management automatically. Models are stored in the `ollama_data` volume.

Ollama dynamically loads and unloads models based on usage, making it memory-efficient when hosting multiple models.

### llama.cpp (port 8081+)

Serves individual GGUF model files via an OpenAI-compatible API. Each instance serves exactly one model. For multiple models, multiple instances run on different ports (8081, 8082, 8083, etc.).

Models are stored in the shared `llamacpp_models` volume, downloaded by the `llamacpp-init` container on first startup.

Unlike Ollama, llama.cpp keeps its model loaded in memory permanently. This means faster response times but dedicated VRAM usage.

### LiteLLM (port 4000)

A lightweight proxy that translates Anthropic's API into OpenAI-compatible format. This is necessary because Open WebUI expects all non-Ollama backends to speak the OpenAI API protocol, but Anthropic uses its own format.

Configuration is in `litellm-config.yaml`. The Anthropic API key is passed via the `.env` file.

### Init Containers

Two one-shot containers run at startup and then exit:

- **ollama-init** — Pulls a default Ollama model (llama3.2:3b) if not already present
- **llamacpp-init** — Downloads GGUF files from HuggingFace into the models volume

These only do work on first run or when new models are added. On subsequent starts they detect existing files and exit immediately.

## Volumes

| Volume | Contents | Safe to delete? |
|---|---|---|
| `openwebui_data` | User accounts, chat history, settings | No — you lose all UI data |
| `ollama_data` | Downloaded Ollama models | Yes — models re-download on pull |
| `llamacpp_models` | Downloaded GGUF files | Yes — re-downloaded by init container |

## Networking

All services communicate over the `ai-stack` Docker bridge network using container names as hostnames (e.g. `http://ollama:11434`). Only the mapped ports are accessible from the host machine.