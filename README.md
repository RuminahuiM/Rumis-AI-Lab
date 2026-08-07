# Rumis AI Lab — as deployed

Dieser Branch bildet ab, was **tatsächlich läuft** — nicht, was geplant war.
Nur verifizierte Konfiguration, ein Ordner pro Deployment-Ziel.

| Ordner | Deployment-Ziel | Status |
|---|---|---|
| [`dgx/`](dgx/) | **DGX Spark** (`spark-753b`) — vLLM-Inferenz-Backend | erfasst am 2026-08-07 |
| [`webserver/`](webserver/) | **Webserver-VM** — LiteLLM, Open WebUI, n8n | noch nicht erfasst |

## Architektur

```
        Webserver-VM                        DGX Spark (spark-753b)
  ┌───────────────────────────┐          ┌────────────────────────────┐
  │  Open WebUI               │          │  vLLM  :8000               │
  │  n8n                      │  ──────► │  gemma-4-26b-a4b-it        │
  │  LiteLLM                  │  /v1/    │  (GB10, arm64)             │
  └───────────────────────────┘          └────────────────────────────┘
         webserver/                                  dgx/
```

Monitoring läuft auf einem **separaten Server**, die Firewall zentral auf der
**Palo Alto** — beides ist nicht Teil dieser Deployments.

## Vorgehen

Erfasst wird ausschliesslich lesend. Verbindliche Quelle sind die
Compose-Labels der laufenden Container, nicht der Repo-Inhalt:

```bash
docker inspect <container> --format \
  '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
```

Jeder Ordner enthält ein `DEPLOYMENT.md` (Schritt für Schritt zum Live-Zustand)
und ein `DRIFT.md` (Abweichungen zum vorherigen Repo-Stand, mit Einschätzung,
welche Variante richtig ist).

## Secrets

Keine echten Secrets im Repo. Die `.env.example`-Dateien führen die echten
Variablennamen mit Platzhaltern; wo die echten Werte liegen, steht im jeweiligen
`DEPLOYMENT.md`. Für den DGX: `/home/adm-dgx/Rumis-AI-Lab/backend/.env`.

## Verhältnis zu den anderen Branches

Der bisherige, nicht gegen das Live-System verifizierte Stand (`backend/`,
`docs/`, `terraform/`, `packer/`, `nginx/` und die Compose-Datei im Root) bleibt
in `claude/docker-setup-guide-ARYXK` und in der Git-Historie erhalten. Auf
diesem Branch ist er entfernt.
