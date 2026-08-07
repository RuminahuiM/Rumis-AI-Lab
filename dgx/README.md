# dgx/ — DGX Spark, wie tatsächlich deployed

Alles, was auf dem DGX Spark (`spark-753b`) gebraucht wird, um das
Inferenz-Backend so laufen zu lassen, wie es aktuell läuft — und nichts sonst.

Erhoben am 2026-08-07, ausschliesslich lesend (`docker inspect`, `docker ps`,
`nvidia-smi`, `ss`, `systemctl`). Am Live-System wurde nichts geändert.

## Auf dem DGX läuft nur vLLM

Monitoring läuft auf einem **separaten Server**, die Firewall zentral auf der
**Palo Alto**. Auf diesem Host ist ausschliesslich vLLM vorgesehen.

vLLM 0.19.0 (arm64, lokal gebautes Image `rumis-vllm:latest`) serviert
`google/gemma-4-26b-a4b-it` unter dem Namen `gemma-4-26b-a4b-it` auf Port 8000.

## Dateien

| Datei | Zweck |
|---|---|
| `docker-compose.yml` | der vLLM-Service — Flags 1:1 wie im laufenden Container |
| `Dockerfile` | baut `rumis-vllm:latest` (nötig, weil `gemma4` neuer ist als die Transformers-Version im Upstream-Image) |
| `.env.example` | Variablennamen der echten `.env`, Werte als Platzhalter |
| `scripts/setup-dgx.sh` | Preflight-Checks für einen frischen DGX (Treiber, Docker, NVIDIA Container Toolkit) |
| `DEPLOYMENT.md` | Schritt für Schritt von frischem DGX zu diesem Zustand |
| `DRIFT.md` | Abweichungen zwischen Repo-Stand und Live-System |

## Was bewusst nicht hier liegt

| | Grund |
|---|---|
| `prometheus`, `grafana`, `dcgm-exporter` | Laufen live auf dem DGX mit, sind aber Überreste vom Go-Live. Monitoring gehört auf den separaten Server. DCGM lief ausserdem nie (amd64-Image auf arm64). Siehe `DRIFT.md` D1 |
| `vllm.service` (systemd) | Ist live **nicht** installiert. Autostart läuft über `restart: unless-stopped`. Siehe `DRIFT.md` D2 |
| `models.yaml` | Wurde von nichts gelesen — reiner Katalog mit einem Eintrag. Die Werte stehen in `.env.example` und `DEPLOYMENT.md` |
| LiteLLM, Open WebUI, n8n | Anderer Tier → `webserver/` |

## Achtung beim Auschecken auf dem DGX

Das Live-Deployment läuft aus `/home/adm-dgx/Rumis-AI-Lab/backend` — also aus
dem Git-Working-Tree selbst — und Prometheus/Grafana binden dort Dateien aus
`backend/monitoring/` ein.

> Diesen Branch **nicht** in `/home/adm-dgx/Rumis-AI-Lab` auschecken. `backend/`
> existiert hier nicht mehr; ein Checkout würde das laufende Deployment samt
> Bind-Mount-Quellen aus dem Verzeichnis entfernen.
>
> Zum Ansehen GitHub benutzen, zum Arbeiten `git worktree add` in ein separates
> Verzeichnis.

Siehe `DRIFT.md` D3.
