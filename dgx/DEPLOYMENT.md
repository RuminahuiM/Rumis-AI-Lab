# DEPLOYMENT.md — Von frischem DGX Spark zum aktuellen Live-Zustand

Diese Anleitung reproduziert **genau den Zustand, der am 2026-08-07 auf
`spark-753b` läuft** — inklusive der bekannten Schwächen. Wo der Live-Zustand
nicht optimal ist, steht ein Verweis auf `DRIFT.md`; solche Punkte sind bewusst
so beschrieben, wie sie real sind, nicht wie sie sein sollten.

**Zielzustand:** vLLM 0.19.0 serviert `google/gemma-4-26b-a4b-it` unter dem
Namen `gemma-4-26b-a4b-it` auf Port 8000.

> **Auf dem DGX Spark soll ausschliesslich vLLM laufen.** Das Monitoring läuft
> auf einem **separaten Server**, die Firewall zentral auf der **Palo Alto**.
>
> Live laufen auf dem DGX zusätzlich noch `prometheus`, `grafana` und
> `dcgm-exporter` aus derselben Compose-Datei — Überreste vom Go-Live. Diese
> Anleitung beschreibt in §5 beide Wege: den **Soll-Weg** (nur vLLM) und den
> Weg, der den Live-Zustand exakt reproduziert. Für ein Redeployment ist der
> Soll-Weg zu nehmen.

---

## 0. Wo die echten Secrets liegen

Es gibt genau **ein** Secret auf dem DGX: den HuggingFace-Token.

> **Die echte `.env` mit den echten Werten liegt auf dem DGX in
> `/home/adm-dgx/Rumis-AI-Lab/backend/.env`.**

Diese Datei ist gitignored und darf nicht ins Repo. `dgx/.env.example` enthält
dieselben Variablennamen mit Platzhaltern; die nicht-geheimen Live-Werte sind
dort als Kommentar dokumentiert.

Für ein Redeployment brauchst du:

| Wert | Quelle |
|---|---|
| `HF_TOKEN` | vom DGX aus `backend/.env`, oder neu erzeugen unter https://huggingface.co/settings/tokens (Read-Zugriff, Lizenz für `google/gemma-4-26b-a4b-it` muss auf dem HF-Account akzeptiert sein) |
| alle übrigen Variablen | nicht geheim, echte Werte siehe `dgx/.env.example` |

---

## 1. Voraussetzungen prüfen

Der Live-Host hat:

| | |
|---|---|
| Architektur | **aarch64 / arm64** (NVIDIA GB10) |
| Treiber | 580.142, CUDA 13.0 |
| Kernel | `6.17.0-1014-nvidia` |
| Disk | eine NVMe, 3.7 TB auf `/` |
| Docker | Engine 29.2.1, Compose-Plugin v5.0.2 |

```bash
uname -m                 # muss aarch64 sein
nvidia-smi               # Treiber + GB10 sichtbar
docker version
docker compose version   # v2 oder neuer (live: v5.0.2)
```

**Die Architektur ist entscheidend.** Auf arm64 muss jedes Image ein
arm64-Manifest haben — der DCGM-Exporter hat genau das nicht (`DRIFT.md` D6).
Vor dem Pull eines Images prüfen:

```bash
docker image inspect <image> --format '{{.Architecture}}'   # muss arm64 sein
```

DGX OS bringt Treiber und NVIDIA Container Toolkit normalerweise mit. Falls
nicht, erledigt das Preflight-Script beides:

```bash
bash dgx/scripts/setup-dgx.sh
```

Es prüft Treiber, Docker, NVIDIA Container Toolkit, führt einen
GPU-in-Container-Smoke-Test aus und kontrolliert die `.env`. Es installiert
Docker und das Container Toolkit, falls sie fehlen — sonst ändert es nichts.

GPU-Zugriff aus einem Container manuell verifizieren:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -L
```

---

## 2. Code ablegen

Live liegt das Deployment in `/home/adm-dgx/Rumis-AI-Lab/backend` — also im
Git-Working-Tree selbst. **Das ist eine der Abweichungen** (`DRIFT.md` D2):
Prometheus und Grafana binden Dateien aus diesem Verzeichnis ein, deshalb kann
ein `git checkout`/`git pull` laufende Bind-Mounts verändern.

Für ein neues Deployment daher getrennt aufsetzen:

```bash
sudo mkdir -p /opt/rumis-ai-lab
sudo chown "$USER" /opt/rumis-ai-lab
git clone <repo-url> /opt/rumis-ai-lab
cd /opt/rumis-ai-lab/dgx
```

**Wichtig — Compose-Projektname.** Der Projektname wird aus dem
Verzeichnisnamen abgeleitet und bestimmt die Volume-Namen. Live heisst das
Verzeichnis `backend`, deshalb heissen die Volumes `backend_huggingface_cache`,
`backend_prometheus_data`, `backend_grafana_data`. Aus `dgx/` heraus würden sie
`dgx_*` heissen — ein anderes Volume-Set, das Modell würde neu geladen. Deshalb
den Projektnamen explizit festlegen:

```bash
export COMPOSE_PROJECT_NAME=backend      # bindet an die bestehenden Volumes
```

oder dauerhaft `name: backend` in `docker-compose.yml` eintragen.

---

## 3. `.env` anlegen

```bash
cp .env.example .env
nano .env
```

Die Werte so setzen, dass sie dem Live-Zustand entsprechen (`HF_TOKEN` aus der
echten `.env` auf dem DGX bzw. neu erzeugen):

```env
HF_TOKEN=hf_...                               # GEHEIM
VLLM_MODEL=google/gemma-4-26b-a4b-it
VLLM_QUANTIZATION=modelopt_fp4                # wirkungslos, siehe DRIFT.md D4
VLLM_MAX_MODEL_LEN=8192
VLLM_GPU_MEMORY_UTILIZATION=0.90
VLLM_TENSOR_PARALLEL_SIZE=1
VLLM_SERVED_MODEL_NAME=gemma-4-26b-a4b-it
```

Zwei Punkte, die beim Go-Live Zeit gekostet haben:

- **`VLLM_SERVED_MODEL_NAME` ohne `google/`-Prefix.** Der Slash in
  `google/gemma-4-26b-a4b-it` bricht die Modell-Auflösung in LiteLLM. Ohne
  dieses Flag ist der Stack Ende-zu-Ende kaputt (`DRIFT.md` D5/D8).
- **`VLLM_QUANTIZATION` wird von der Compose-Datei nicht gelesen.** Der
  laufende Container hat kein `--quantization`-Flag; das Modell läuft
  unquantisiert. Die Zeile existiert live, wirkt aber nicht (`DRIFT.md` D4).
  Sie ist hier nur enthalten, um den Live-Zustand exakt abzubilden.

Rechte setzen, damit der Token nicht world-readable ist:

```bash
chmod 600 .env
```

---

## 4. Image bauen

vLLM läuft **nicht** aus dem Upstream-Image, sondern aus einem lokal gebauten
`rumis-vllm:latest`. Grund: Die Architektur `gemma4` ist neuer als die
Transformers-Version in `vllm/vllm-openai:latest` — das `Dockerfile` installiert
Transformers aus dem Git-Master nach.

```bash
docker compose build
```

Ergebnis live:

| | |
|---|---|
| Image | `rumis-vllm:latest`, arm64 |
| Basis | `vllm/vllm-openai:latest` (Entrypoint `["vllm","serve"]`) |
| vLLM | 0.19.0 |
| transformers | 5.6.0.dev0 (aus Git-Master) |

> Der Build zieht `git+https://github.com/huggingface/transformers.git` **ohne
> Pin**. Ein Rebuild zu einem späteren Zeitpunkt ergibt eine andere
> Transformers-Version und ist damit nicht bit-identisch zum Live-Image. Wer
> exakt reproduzieren will, pinnt den Commit im `Dockerfile`.

---

## 5. Starten

### Soll-Weg: nur vLLM (empfohlen)

```bash
docker compose up -d vllm
docker compose logs -f vllm
```

Der explizite Service-Name startet **nur** vLLM. `prometheus`, `grafana` und
`dcgm-exporter` bleiben aus — sie gehören auf den separaten Monitoring-Server
(`DRIFT.md` D3). Für ein sauberes Redeployment die drei Services zusätzlich aus
`docker-compose.yml` entfernen, damit ein späteres `docker compose up -d` ohne
Argument sie nicht doch wieder hochzieht; ebenso `monitoring/` und
`MONITORING.md`.

Auf dem Monitoring-Server wird vLLM dann remote gescrapt, statt über das
Compose-Netz:

```yaml
scrape_configs:
  - job_name: vllm-dgx
    static_configs:
      - targets: ['10.200.108.10:8000']
```

### Live-Weg: alle vier Services (reproduziert den Ist-Zustand)

```bash
docker compose up -d
docker compose logs -f vllm
```

Der erste Start lädt das Modell von HuggingFace (~15 GB) in das Volume
`backend_huggingface_cache`. Der Healthcheck hat `start_period: 300s`, damit
der Download nicht als Fehler gilt. Spätere Starts sind schnell, weil das
Modell im Volume liegt.

Erwartetes Ergebnis:

```
vllm            rumis-vllm:latest                        Up (healthy)   0.0.0.0:8000->8000/tcp
prometheus      prom/prometheus:latest                   Up             0.0.0.0:9090->9090/tcp
grafana         grafana/grafana:latest                   Up             0.0.0.0:3000->3000/tcp
dcgm-exporter   nvcr.io/nvidia/k8s/dcgm-exporter:latest  Restarting (255)
```

**`dcgm-exporter` im Crashloop ist der korrekte Live-Zustand** — nicht ein
Fehler dieser Anleitung. Das Image ist amd64-only und startet auf arm64 nie
(`DRIFT.md` D6). Damit gibt es keine GPU-Metriken; alle `DCGM_FI_DEV_*`-Panels
bleiben leer. Wer das nicht reproduzieren will, kommentiert den Service aus.

---

## 6. Verifizieren

```bash
# Health
curl -sf http://localhost:8000/health

# Modell-Liste — muss "gemma-4-26b-a4b-it" liefern, NICHT "google/..."
curl -s http://localhost:8000/v1/models

# Inferenz-Test (Modellname ohne google/-Prefix!)
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gemma-4-26b-a4b-it","messages":[{"role":"user","content":"Hallo"}]}'
```

Live-Antwort von `/v1/models`:

```json
{"object":"list","data":[{"id":"gemma-4-26b-a4b-it","object":"model",
 "owned_by":"vllm","root":"google/gemma-4-26b-a4b-it","max_model_len":8192}]}
```

Monitoring:

```bash
# Prometheus-Targets: vllm=UP, dcgm=DOWN (erwartet, siehe D6)
curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"[a-z]*"'
```

- Grafana: `http://<dgx-ip>:3000` — anonymer Viewer-Zugang, kein Login.
  Dashboard im Ordner **vLLM**. Die Template-Variable `model_name` steht per
  Default auf einem Llama-3-Pfad aus dem Upstream-Sample und muss auf
  `gemma-4-26b-a4b-it` umgestellt werden, sonst zeigen alle Panels „No data"
  (`DRIFT.md` D7).
- vLLM exportiert Metriken erst **nach dem ersten Request**. Vorher wirkt das
  Target so, als wäre es leer.

---

## 7. Autostart

**Live ist kein systemd-Unit installiert** (`DRIFT.md` D1). Der Autostart hängt
allein an:

```yaml
restart: unless-stopped     # in docker-compose.yml, alle vier Services
```

zusammen mit `systemctl is-enabled docker` → `enabled`. Das überlebt einen
Reboot und ist der Grund, warum der fehlende Unit nie aufgefallen ist.

Zum Reproduzieren des Live-Zustands: **nichts tun.**

Wer den Start explizit machen will (empfohlen), muss `dgx/vllm.service`
**anpassen** — das `WorkingDirectory` darin zeigt auf `/opt/rumis-ai-lab/backend`,
was live nicht existiert:

```bash
# WorkingDirectory auf das echte Deployment-Verzeichnis korrigieren, dann:
sudo cp dgx/vllm.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vllm
```

---

## 8. Was diese Anleitung bewusst NICHT herstellt

Der Live-Zustand hat Lücken, die ein Redeployment nicht kopieren sollte. Sie
sind hier gelistet, weil sie sonst still mitwandern:

| Punkt | Live-Zustand | Empfehlung | Ref |
|---|---|---|---|
| Monitoring-Services | `prometheus`, `grafana`, `dcgm-exporter` laufen mit | **Auf dem DGX nur vLLM starten** — Monitoring läuft auf einem separaten Server | D3 |
| DCGM | Crashloop, 152 410 Restarts, keine GPU-Metriken | Service vom DGX entfernen (nicht: arm64-Image suchen) | D6 |
| `HF_HUB_OFFLINE` | nicht gesetzt (=0) → jeder Start braucht Internet + gültigen Token | nach dem ersten Download auf `1` setzen | D12 |
| Backups | keine — kein Cron, keine Timer | für den DGX vertretbar (Zustand ist reproduzierbar); bewusst dokumentieren | D14 |
| Transformers-Pin | `git+…/transformers.git` ohne Commit-Pin | Commit pinnen für reproduzierbare Builds | §4 |

**Kein Handlungsbedarf**, obwohl es zunächst wie eine Lücke aussieht: Auf dem
DGX ist `ufw` deaktiviert und Port 8000 lauscht auf `0.0.0.0`. Die
Segmentierung erfolgt **zentral auf der Palo Alto** — ein zweites Regelwerk auf
dem Host ist nicht gewollt (`DRIFT.md` D10/D11).

---

## 9. Anbindung der Webserver-VM

Der DGX ist unter zwei internen Adressen erreichbar:

| Interface | Adresse | |
|---|---|---|
| `bond0` | `10.200.108.10` | Default-Route via `10.200.108.254` |
| `enP7s7` | `10.200.200.40` | zweites internes Netz |

Auf der Webserver-VM wird das als `VLLM_ENDPOINT` konfiguriert. Zwei Dinge
müssen stimmen:

```env
VLLM_ENDPOINT=http://10.200.108.10:8000/v1/
```

- **Trailing Slash `/v1/` ist zwingend.** Ohne ihn ersetzt der OpenAI-Client
  `/v1` per RFC 3986 durch den Endpoint-Pfad und vLLM antwortet 404
  (`DRIFT.md` D9).
- **Der Modellname in `litellm-config.yaml` muss ohne `google/`-Prefix stehen:**
  `model: openai/gemma-4-26b-a4b-it` (`DRIFT.md` D8).

Welche der beiden Adressen real benutzt wird und was exakt in der
`litellm-config.yaml` der VM steht, ist von hier aus nicht feststellbar und im
zweiten Erfassungsschritt zu klären — siehe `webserver/README.md`.
