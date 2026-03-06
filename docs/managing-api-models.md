# Managing API Models (Anthropic, OpenAI, Gemini)

Cloud-hosted models from Anthropic, OpenAI, and Google Gemini are all managed through **LiteLLM**, which acts as a translation proxy. This guide covers how to add, remove, and configure these models.

---

## How It Works

LiteLLM translates all cloud APIs into a single OpenAI-compatible format that Open WebUI understands. Configuration happens in two places:

- **`.env`** — API keys for each provider
- **`litellm-config.yaml`** — Which models to expose and under what names

After any change, restart LiteLLM:
```bash
docker compose restart litellm
```
Then refresh connections in Open WebUI (Settings → Admin Settings → Connections).

---

## Setting Up a Provider

### Step 1: Get an API key

| Provider | Where to get a key |
|---|---|
| Anthropic | [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) |
| OpenAI | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| Google Gemini | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) |

### Step 2: Add the key to `.env`

```env
ANTHROPIC_API_KEY=sk-ant-your-key-here
OPENAI_API_KEY=sk-your-key-here
GEMINI_API_KEY=your-key-here
```

### Step 3: Make sure docker-compose.yml passes it to LiteLLM

The LiteLLM service needs the key as an environment variable:

```yaml
  litellm:
    environment:
      ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}"
      OPENAI_API_KEY: "${OPENAI_API_KEY}"
      GEMINI_API_KEY: "${GEMINI_API_KEY}"
```

### Step 4: Add models in `litellm-config.yaml`

See the sections below for the format.

---

## Adding a Model

Add an entry to `model_list` in `litellm-config.yaml`:

```yaml
  - model_name: my-display-name
    litellm_params:
      model: provider/model-id
      api_key: os.environ/ENV_VAR_NAME
```

The three parts are:

- **`model_name`** — The name shown in Open WebUI's model picker. Choose whatever you want.
- **`model`** — The provider prefix + official model ID. The prefix tells LiteLLM which API format to use.
- **`api_key`** — Always use `os.environ/...` to reference the key from `.env`. Never paste keys directly into this file.

### Provider prefixes

| Provider | Prefix | Example |
|---|---|---|
| Anthropic | `anthropic/` | `anthropic/claude-sonnet-4-20250514` |
| OpenAI | `openai/` | `openai/gpt-4o` |
| Google Gemini | `gemini/` | `gemini/gemini-2.5-pro-preview-06-05` |

### Example: Adding a new Anthropic model

```yaml
  - model_name: claude-new-model
    litellm_params:
      model: anthropic/claude-new-model-20260101
      api_key: os.environ/ANTHROPIC_API_KEY
```

### Example: Adding a new OpenAI model

```yaml
  - model_name: gpt-5
    litellm_params:
      model: openai/gpt-5
      api_key: os.environ/OPENAI_API_KEY
```

### Example: Adding a new Gemini model

```yaml
  - model_name: gemini-3-pro
    litellm_params:
      model: gemini/gemini-3.0-pro
      api_key: os.environ/GEMINI_API_KEY
```

After adding, restart:
```bash
docker compose restart litellm
```

---

## Removing a Model

Delete or comment out the entry in `litellm-config.yaml`:

```yaml
  # - model_name: gpt-4o-mini
  #   litellm_params:
  #     model: openai/gpt-4o-mini
  #     api_key: os.environ/OPENAI_API_KEY
```

Then restart:
```bash
docker compose restart litellm
```

The model disappears from Open WebUI after refreshing connections.

---

## Disabling an Entire Provider

If you don't want to use a provider at all (e.g. you don't have an OpenAI key):

1. Remove (or comment out) all models from that provider in `litellm-config.yaml`
2. Leave the key empty or remove it from `.env`
3. Optionally remove the environment variable from the LiteLLM service in `docker-compose.yml`

LiteLLM won't crash if a key is missing — it simply won't be able to call those models. But removing the model entries keeps the config clean.

---

## Renaming a Model

Just change the `model_name` field. This is purely a display name — it doesn't affect which model is actually called:

```yaml
  # Instead of this:
  - model_name: claude-sonnet-4-20250514

  # You could use this:
  - model_name: Claude Sonnet 4
```

You can also rename models inside Open WebUI under Settings → Admin Settings → Models, which doesn't require a LiteLLM restart.

---

## Finding Model IDs

When a provider releases a new model, you need the official model ID to add it.

- **Anthropic:** [docs.anthropic.com/en/docs/about-claude/models](https://docs.anthropic.com/en/docs/about-claude/models)
- **OpenAI:** [platform.openai.com/docs/models](https://platform.openai.com/docs/models)
- **Google Gemini:** [ai.google.dev/gemini-api/docs/models](https://ai.google.dev/gemini-api/docs/models)
- **LiteLLM supported models:** [docs.litellm.ai/docs/providers](https://docs.litellm.ai/docs/providers)

LiteLLM supports many more providers beyond these three (Mistral, Cohere, Azure, AWS Bedrock, etc.). Check the LiteLLM docs for the full list and their prefix/configuration format.

---

## Adding a Completely New Provider

LiteLLM supports dozens of providers. The pattern is always the same:

1. Add the API key to `.env`:
   ```env
   MISTRAL_API_KEY=your-key-here
   ```

2. Pass it to LiteLLM in `docker-compose.yml`:
   ```yaml
     litellm:
       environment:
         MISTRAL_API_KEY: "${MISTRAL_API_KEY}"
   ```

3. Add models to `litellm-config.yaml`:
   ```yaml
     - model_name: mistral-large
       litellm_params:
         model: mistral/mistral-large-latest
         api_key: os.environ/MISTRAL_API_KEY
   ```

4. Restart:
   ```bash
   docker compose restart litellm
   ```

Check [docs.litellm.ai/docs/providers](https://docs.litellm.ai/docs/providers) for the correct prefix and model IDs for each provider.

---

## Full Example Config

A minimal config with one model per provider:

```yaml
model_list:
  - model_name: claude-sonnet-4
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY

  - model_name: gemini-2.5-pro
    litellm_params:
      model: gemini/gemini-2.5-pro-preview-06-05
      api_key: os.environ/GEMINI_API_KEY

general_settings:
  master_key: null
  drop_params: true
```