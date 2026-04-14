# Architecture

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Docker Network (ai-stack)                    │
│                                                                 │
│  ┌──────────┐    Ollama API     ┌────────────────────────┐      │
│  │  Ollama   │◄────────────────►│                        │      │
│  │ :11434    │◄────────┐       │     Open WebUI          │      │
│  └──────────┘         │       │     :3000               │      │
│       ▲               │       │                        │      │
│       │               │       └──────────┬─────────────┘      │
│       │               │                  │ MCP (SSE)           │
│       │           ┌───┴────────┐         │   ▼                 │
│  ┌────┴─────┐     │  OpenClaw  │    ┌────┴──────────┐          │
│  │ llama.cpp │     │  :18789   │    │   n8n         │          │
│  │ :8081     │     │  (agent)  │    │   :5678       │          │
│  └──────────┘     └───┬────────┘    │  (MCP server) │          │
│       ▲               │  MCP tools  └───────────────┘          │
│       │               └──────────►                              │
│       │           ┌──────────────┐                              │
│       │           │   LiteLLM    │                              │
│       └──────────►│   :4000      │                              │
│         OpenAI API│              │                              │
│                   │  Claude, GPT,│                              │
│                   │  Gemini      │                              │
│                   └──────┬───────┘                              │
│                          │                                      │
│                   api.anthropic.com                             │
│                   api.openai.com                                │
│                   generativelanguage.google                     │
└─────────────────────────────────────────────────────────────────┘
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

A lightweight proxy that translates Anthropic, OpenAI, and Google Gemini APIs into OpenAI-compatible format. This is necessary because Open WebUI and OpenClaw expect backends to speak the OpenAI API protocol.

Configuration is in `litellm-config.yaml`. API keys are passed via the `.env` file. LiteLLM acts as a security boundary — neither Open WebUI nor OpenClaw hold any cloud API keys directly.

### OpenClaw (port 18789)

An autonomous AI agent that can execute tasks, manage files, call APIs, and maintain long-term memory. Unlike Open WebUI (which is a chat interface), OpenClaw acts independently and can perform multi-step workflows.

OpenClaw connects to all model backends through the Docker network: Ollama for local models, llama.cpp for GGUF models, and LiteLLM for cloud models. It holds zero API keys — all cloud access goes through LiteLLM.

The gateway is token-authenticated and bound to localhost only. An `openclaw-cli` service (in the `cli` profile) provides management commands but doesn't auto-start.

Data is stored locally in `openclaw/config/` (agent memory, settings) and `openclaw/workspace/` (files the agent creates).

### n8n (port 5678)

A visual workflow automation platform that doubles as an **MCP (Model Context
Protocol) server** for the stack. Using n8n's built-in MCP Server Trigger node,
any workflow can be exposed as an AI-callable tool — giving Open WebUI and
OpenClaw access to 400+ integrations (Gmail, Slack, GitHub, databases, HTTP
APIs, and more) without holding any credentials themselves.

All third-party secrets are stored in n8n's encrypted credential store. The AI
receives only tool results, never the underlying credentials.

See [docs/n8n-mcp-setup.md](n8n-mcp-setup.md) for setup instructions.

### Init Containers

Two one-shot containers run at startup and then exit:

- **ollama-init** — Pulls a default Ollama model (llama3.2:3b) if not already present
- **llamacpp-init** — Downloads GGUF files from HuggingFace into the models volume

These only do work on first run or when new models are added. On subsequent starts they detect existing files and exit immediately.

## Volumes and Data

| Storage | Type | Contents | Safe to delete? |
|---|---|---|---|
| `openwebui_data` | Docker volume | User accounts, chat history, settings | No — you lose all UI data |
| `ollama_data` | Docker volume | Downloaded Ollama models | Yes — models re-download on pull |
| `llamacpp_models` | Docker volume | Downloaded GGUF files | Yes — re-downloaded by init container |
| `openclaw/config/` | Local directory | Agent config, memory, gateway token | No — you lose agent state |
| `openclaw/workspace/` | Local directory | Files the agent creates | Depends — may contain important work |

## Networking

All services communicate over the `ai-stack` Docker bridge network using container names as hostnames (e.g. `http://ollama:11434`). Only the mapped ports are accessible from the host machine.