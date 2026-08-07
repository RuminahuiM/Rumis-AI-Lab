# dgx/ — DGX Spark, wie tatsächlich deployed

Dieser Ordner ist eine **1:1-Abbildung des am 2026-08-07 real laufenden
Inferenz-Backends** auf dem DGX Spark (Hostname `spark-753b`). Nicht der
Soll-Zustand aus der Planung, sondern der Ist-Zustand.

Erhoben ausschliesslich lesend (`docker inspect`, `docker ps`, `nvidia-smi`,
`ss`, `systemctl`). Am Live-System wurde nichts geändert.

## Dateien

| Datei | Herkunft |
|---|---|
| `docker-compose.yml` | 1:1 aus `/home/adm-dgx/Rumis-AI-Lab/backend/docker-compose.yml` |
| `Dockerfile` | 1:1, baut `rumis-vllm:latest` aus `vllm/vllm-openai:latest` |
| `models.yaml` | 1:1 (reine Referenz, wird nicht von Compose gelesen) |
| `monitoring/` | 1:1, Prometheus-Config + Grafana-Provisioning (Bind-Mounts) — gehört nicht auf den DGX, siehe DRIFT.md D3 |
| `scripts/setup-dgx.sh` | 1:1, Preflight-Checks |
| `vllm.service` | 1:1 — **liegt im Repo, ist aber NICHT installiert**, siehe DRIFT.md D1 |
| `MONITORING.md` | 1:1 |
| `.env.example` | Variablennamen der echten `.env`, Werte als Platzhalter |
| `DEPLOYMENT.md` | Schritt-für-Schritt von frischem DGX zu diesem Zustand |
| `DRIFT.md` | Alle Abweichungen Repo ↔ Live |

## Soll-Zustand auf dem DGX: nur vLLM

**Auf dem DGX Spark muss ausschliesslich vLLM laufen.** Monitoring wird von
einem **separaten Server** übernommen, nicht von diesem Host. Die Firewall ist
zentral auf der **Palo Alto** geregelt — nicht auf dem DGX.

## Live-Zustand in einem Satz

vLLM 0.19.0 (arm64, Image `rumis-vllm:latest`) serviert
`google/gemma-4-26b-a4b-it` als `gemma-4-26b-a4b-it` auf Port 8000.

Zusätzlich laufen in derselben Compose-Datei noch `prometheus` (9090),
`grafana` (3000) und `dcgm-exporter` (9400, Dauer-Crashloop) — **Überreste vom
Go-Live**. Sie sind hier nicht erwünscht, da das Monitoring auf dem separaten
Server stattfindet. Sie sind in diesem Ordner 1:1 dokumentiert, weil sie real
laufen; zum Abräumen siehe `DRIFT.md` D3/D6.

## Wichtiger Hinweis zum Auschecken

Das Live-Deployment läuft aus **genau diesem Repo-Verzeichnis**
(`/home/adm-dgx/Rumis-AI-Lab/backend`, Compose-Projekt `backend`), und
Prometheus/Grafana binden Dateien aus `backend/monitoring/` direkt ein.

> Einen anderen Branch in `/home/adm-dgx/Rumis-AI-Lab` auszuchecken verändert
> damit **laufende Bind-Mount-Quellen**. `git checkout live/as-deployed` würde
> dort `backend/monitoring/*` löschen (dieser Branch stammt von
> `claude/fork-new-setup-XOPpb`, wo das Monitoring noch fehlt).
>
> Für Arbeiten an diesem Branch auf dem DGX deshalb `git worktree add` in ein
> separates Verzeichnis benutzen, nicht das Hauptverzeichnis umschalten.

Siehe DRIFT.md D2 — dass das Deployment aus einem Git-Working-Tree läuft, ist
selbst eine der Abweichungen.
