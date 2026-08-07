# webserver/ — Platzhalter

Dieser Ordner beschreibt **die separate Webserver-VM** (Tier 2) des
Rumis-AI-Lab: LiteLLM, Open WebUI und n8n.

## Status: noch nicht erfasst

Der Inhalt dieses Ordners wird in einem **zweiten Schritt direkt auf der
Webserver-VM** aus dem echt laufenden System übernommen — analog zu `dgx/`,
das aus dem Live-Zustand des DGX Spark erzeugt wurde.

Der bestehende Repo-Stand für diesen Tier liegt bis dahin unverändert im
Repo-Root (`docker-compose.yml`, `litellm-config.yaml`, `.env.example`,
`nginx/`) und ist **nicht** gegen das Live-System verifiziert.

## Was auf der Webserver-VM zu erfassen ist

Auf der VM dieselbe Methode anwenden wie auf dem DGX — die Compose-Labels
sind die verbindliche Quelle, nicht das, was im Repo steht:

```bash
docker ps -a
for c in $(docker ps -aq); do
  docker inspect "$c" --format \
    '{{.Name}} {{index .Config.Labels "com.docker.compose.project.working_dir"}} {{index .Config.Labels "com.docker.compose.project.config_files"}}'
done
```

Konkrete Punkte:

| Thema | Was genau |
|---|---|
| Container | LiteLLM, Open WebUI, n8n, ggf. nginx/Reverse Proxy, DB (Postgres?), Redis? — mit Images und Tags |
| Compose-Projekt | `working_dir` + `config_files` je Container; daraus die echte Compose-Datei lesen |
| `.env` | Variablennamen 1:1; Werte durch `<ECHTER-WERT-AUF-WEBSERVER>` ersetzen |
| `litellm-config.yaml` | Live-Version — insb. `model_name` und `model:` (mit/ohne `google/`-Prefix) und `api_base` |
| `VLLM_ENDPOINT` | Welche DGX-IP wird real benutzt: `10.200.108.10` (bond0) oder `10.200.200.40` (enP7s7)? Mit oder ohne `/v1/`-Trailing-Slash? |
| SSO / Azure AD | Gesetzte OIDC-Variablen, `OPENID_REDIRECT_URI`, App-Proxy-Hostname |
| Reverse Proxy | nginx/Caddy-Config, TLS-Zertifikate, Azure App Proxy Connector |
| Persistenz | Docker-Volumes bzw. Bind-Mounts (Open WebUI SQLite, n8n-Daten, LiteLLM-DB) |
| systemd | Gibt es Units, oder hängt alles an `restart: unless-stopped`? (auf dem DGX: kein systemd, siehe `dgx/DRIFT.md` D1) |
| Netzwerk/Firewall | `ufw status`, offene Ports, wie erreicht die VM Port 8000 des DGX |
| Backups | Cron/Timer für n8n- und Open-WebUI-Daten? |

## Ergebnis dieses zweiten Schritts

- `webserver/docker-compose.yml` — real verwendete Compose-Datei
- `webserver/litellm-config.yaml` — real verwendete LiteLLM-Config
- `webserver/.env.example` — echte Variablennamen, Platzhalter-Werte
- `webserver/nginx/` bzw. Proxy-Config, falls vorhanden
- `webserver/DEPLOYMENT.md` — Schritt-für-Schritt zum Live-Zustand
- `webserver/DRIFT.md` — Abweichungen Repo ↔ Live auf der VM
