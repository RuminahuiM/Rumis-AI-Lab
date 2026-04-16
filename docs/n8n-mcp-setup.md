# n8n as MCP Server

n8n ships a built-in **MCP Server Trigger** node (v1.68+). This lets you expose
any n8n workflow as an MCP tool — so Open WebUI can call real-world integrations
(Gmail, Slack, GitHub, databases, HTTP APIs, and 400+ more) directly from chat.

No extra containers are needed. n8n is already in the stack and already on the
right Docker networks to be reached by Open WebUI.

---

## How it works

```
┌────────────────┐         MCP / SSE          ┌──────────────────────────┐
│  Open WebUI    │ ──────────────────────────► │                          │
│  (chat + tools)│                             │  n8n  :5678              │
└────────────────┘                             │  (MCP Server Trigger)    │
                                               │                          │
                                               │  Workflows can reach:    │
                                               │  Gmail, Slack, GitHub,   │
                                               │  HTTP, Postgres, ...     │
                                               └──────────────────────────┘
```

1. You create a workflow in n8n that starts with an **MCP Server Trigger** node.
2. n8n exposes it as an MCP endpoint at `http://n8n:5678/mcp` (SSE transport).
3. Open WebUI connects to that URL and auto-discovers the available tools.
4. During a chat, the LLM can invoke a tool → n8n executes the workflow → result
   comes back into the conversation.

All credentials (API keys, OAuth tokens) live in n8n's encrypted credential
store. The AI never sees them.

---

## Step 1: Create an MCP tool workflow in n8n

1. Open n8n at `http://<lan-ip>:5678` (local) or `https://n8n.<domain>` (server).
2. Complete the setup wizard on first run to create your admin account.
3. Click **+ New workflow**.
4. Click **Add first step** → search for **MCP Server Trigger** → select it.
5. The trigger node gives you an MCP endpoint URL. Note the path shown (something
   like `/mcp/your-workflow-path/sse`).
6. Add your action nodes after the trigger. For example:
   - **HTTP Request** → call any external API
   - **Gmail** → send an email
   - **Slack** → post a message
   - **Postgres / MySQL** → query a database
7. Add a **Respond to MCP** node at the end to return the result to the caller.
8. **Activate** the workflow (toggle in the top-right corner). The MCP endpoint
   is only live when the workflow is active.

---

## Step 2: Connect Open WebUI

1. In Open WebUI, go to **Admin Panel → Tools**.
2. Click **Add MCP Server**.
3. Enter the URL: `http://n8n:5678/mcp` (Docker-internal hostname, no port
   forwarding needed).
4. Save. Open WebUI discovers all active MCP tools automatically.
5. In a chat session, click the **Tools** icon and enable the tools you want the
   model to use.

> **Note:** The model must support tool/function calling. All Claude models,
> GPT-4+, and Gemini 1.5+ support this. Select one of those in the chat.

---

## Example starter tools to build

### 1. Web fetch / summarise a URL

```
MCP Server Trigger → HTTP Request (GET any URL) → Respond to MCP
```

The AI calls this tool with a URL and gets back the page content to summarise
or extract data from.

### 2. Send a Slack notification

```
MCP Server Trigger → Slack (Post Message) → Respond to MCP
```

Configure a Slack credential in n8n. The AI can now send messages to any
channel on request.

### 3. List available AI models

```
MCP Server Trigger → HTTP Request (GET http://litellm:4000/v1/models) → Respond to MCP
```

A meta-tool that lets the AI query which models are available in the stack.
Uses the internal Docker hostname — no internet call needed.

### 4. Query a database

```
MCP Server Trigger → Postgres / MySQL node → Respond to MCP
```

Add your database credentials in n8n and the AI can run read queries safely
(scope permissions to read-only in the DB).

---

## Security notes

- **Credentials stay in n8n.** Third-party API keys (Slack tokens, Gmail OAuth,
  database passwords) are stored encrypted in n8n's credential store. The AI
  receives only the tool result, never the credential.
- **The MCP endpoint is internal-only.** `http://n8n:5678` is only reachable
  inside the Docker network. It is not exposed to the internet directly. On the
  server setup it is proxied through nginx with HTTPS.
- **Scope your tools carefully.** Only activate workflows you trust the AI to
  call. Destructive operations (delete, send, publish) should have a human
  confirmation step or be gated by a parameter check in the workflow.
- **n8n authentication.** On first run, set a strong password for your n8n
  account. On the server setup, n8n is behind nginx HTTPS — do not expose port
  5678 directly.

---

## Troubleshooting

**Open WebUI shows "no tools found" after adding the MCP server URL**
→ Make sure the workflow is **activated** in n8n (the toggle in the top-right
  must be on). Inactive workflows do not expose an MCP endpoint.

**Connection refused / timeout when adding `http://n8n:5678/mcp`**
→ Confirm n8n is running: `docker compose ps n8n`
→ Check n8n logs: `docker compose logs n8n --tail=30`

**Tool call returns an error**
→ Open n8n → Executions (left sidebar) to see the full execution log and
  exactly which node failed.

**Webhook/MCP URL shown in n8n is wrong (shows localhost instead of your domain)**
→ Make sure `N8N_HOST` and `WEBHOOK_URL` are set correctly in your `.env` file
  and the container was restarted after the change.
  (`docker compose up -d n8n`)
