# DEPLOYMENT.md — Von frischem DGX Spark zum Live-Zustand

Diese Anleitung bringt einen frischen DGX Spark in den Zustand, in dem
`spark-753b` am 2026-08-07 läuft.

**Zielzustand:** vLLM 0.19.0 serviert `google/gemma-4-26b-a4b-it` unter dem
Namen `gemma-4-26b-a4b-it` auf Port 8000. Sonst nichts — Monitoring läuft auf
einem separaten Server, die Firewall zentral auf der Palo Alto.

---

## 0. Wo die echten Secrets liegen

Es gibt genau **ein** Secret auf dem DGX: den HuggingFace-Token.

> **Die echte `.env` liegt auf dem DGX in
> `/home/adm-dgx/Rumis-AI-Lab/backend/.env`.**

Diese Datei ist gitignored und darf nicht ins Repo. `.env.example` enthält
dieselben Variablennamen mit Platzhaltern; die nicht-geheimen Live-Werte stehen
dort als Kommentar.

| Wert | Quelle |
|---|---|
| `HF_TOKEN` | vom DGX aus `backend/.env`, oder neu erzeugen unter https://huggingface.co/settings/tokens — Read-Zugriff, und die Lizenz für `google/gemma-4-26b-a4b-it` muss auf dem HF-Account akzeptiert sein |
| alle übrigen | nicht geheim, echte Werte siehe `.env.example` |

---

## 1. Voraussetzungen

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
docker compose version   # v2 oder neuer (live: v5.0.2)
```

**Die Architektur ist entscheidend.** Auf arm64 muss jedes Image ein
arm64-Manifest haben. Genau daran ist der DCGM-Exporter gescheitert, der
monatelang unbemerkt im Crashloop lief (`DRIFT.md` D1). Vor dem Einsatz eines
Images prüfen:

```bash
docker image inspect <image> --format '{{.Architecture}}'   # muss arm64 sein
```

DGX OS bringt Treiber und NVIDIA Container Toolkit normalerweise mit. Falls
nicht, installiert das Preflight-Script beides und prüft den Rest:

```bash
bash dgx/scripts/setup-dgx.sh
```

GPU-Zugriff aus einem Container manuell verifizieren:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -L
```

---

## 2. Code ablegen

Live liegt das Deployment in `/home/adm-dgx/Rumis-AI-Lab/backend`, also im
Git-Working-Tree selbst. **Das ist eine der Abweichungen** (`DRIFT.md` D3):
ein `git checkout`/`git pull` kann dort laufende Bind-Mount-Quellen verändern.
Für ein neues Deployment daher getrennt aufsetzen:

```bash
sudo mkdir -p /opt/rumis-ai-lab
sudo chown "$USER" /opt/rumis-ai-lab
git clone <repo-url> /opt/rumis-ai-lab
cd /opt/rumis-ai-lab/dgx
```

`docker-compose.yml` setzt den Projektnamen explizit auf **`rumis-dgx`**, damit
er nicht vom Verzeichnisnamen abhängt — er bestimmt die Volume-Namen. Das
Modell landet also in `rumis-dgx_huggingface_cache`.

> **Auf `spark-753b` nicht ungeprüft starten.** Dort läuft das Live-Projekt
> `backend` mit dem Volume `backend_huggingface_cache`. Ein `docker compose up`
> aus `dgx/` würde als Projekt `rumis-dgx` einen **zweiten** vLLM-Container
> starten, der auf Port 8000 und um die GPU konkurriert, und das Modell erneut
> herunterladen. Der eigene Projektname ist bewusst so gewählt, dass er das
> laufende Projekt nicht überschreibt — aber parallel starten darf man trotzdem
> nicht.

---

## 3. `.env` anlegen

```bash
cp .env.example .env
nano .env
chmod 600 .env
```

Werte entsprechend dem Live-Zustand:

```env
HF_TOKEN=hf_...                               # GEHEIM
VLLM_MODEL=google/gemma-4-26b-a4b-it
VLLM_MAX_MODEL_LEN=8192
VLLM_GPU_MEMORY_UTILIZATION=0.90
VLLM_TENSOR_PARALLEL_SIZE=1
VLLM_SERVED_MODEL_NAME=gemma-4-26b-a4b-it
```

Der Punkt, der beim Go-Live Zeit gekostet hat: **`VLLM_SERVED_MODEL_NAME` ohne
`google/`-Prefix.** Der Slash in `google/gemma-4-26b-a4b-it` bricht die
Modell-Auflösung in LiteLLM; ohne dieses Flag ist der Stack Ende-zu-Ende kaputt
(`DRIFT.md` D4/D5).

In der Live-`.env` steht zusätzlich `VLLM_QUANTIZATION=modelopt_fp4`. Die
Variable wird von der Compose-Datei **nicht gelesen** — der Container läuft ohne
`--quantization`. Sie kann weggelassen werden, ohne dass sich etwas ändert
(`DRIFT.md` D7).

---

## 4. Image bauen

vLLM läuft **nicht** aus dem Upstream-Image, sondern aus einem lokal gebauten
`rumis-vllm:latest`: die Architektur `gemma4` ist neuer als die
Transformers-Version in `vllm/vllm-openai:latest`, deshalb installiert das
`Dockerfile` Transformers aus dem Git-Master nach.

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

> Der Build zieht Transformers **ohne Commit-Pin**. Ein späterer Rebuild ergibt
> eine andere Version und ist nicht identisch zum Live-Image. Für exakte
> Reproduzierbarkeit den Commit im `Dockerfile` pinnen (`DRIFT.md` D9).

---

## 5. Starten

```bash
docker compose up -d
docker compose logs -f vllm
```

Der erste Start lädt das Modell von HuggingFace (~15 GB) in das Volume. Der
Healthcheck hat `start_period: 300s`, damit der Download nicht als Fehler gilt.
Spätere Starts sind schnell, weil das Modell im Volume liegt.

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

vLLM exportiert Metriken unter `/metrics` erst **nach dem ersten Request** —
vorher wirkt der Endpoint leer. Das ist der Endpoint, den der
Monitoring-Server abfragt.

---

## 7. Autostart

**Es ist kein systemd-Unit installiert** (`DRIFT.md` D2). Der Autostart hängt
allein an:

```yaml
restart: unless-stopped     # in docker-compose.yml
```

zusammen mit `systemctl is-enabled docker` → `enabled`. Das übersteht einen
Reboot und ist der Grund, warum der fehlende Unit nie aufgefallen ist.

Zum Reproduzieren des Live-Zustands: **nichts weiter tun.** Wer den Start
explizit machen will, legt einen Unit mit dem **echten** Deployment-Pfad an —
der frühere `vllm.service` im Repo zeigte auf `/opt/rumis-ai-lab/backend`, was
nicht existierte, und ist deshalb nicht mehr Teil dieses Ordners:

```ini
[Unit]
Description=Rumis AI Lab – vLLM Backend
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/opt/rumis-ai-lab/dgx     # an das echte Verzeichnis anpassen
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
```

---

## 8. Was diese Anleitung bewusst NICHT herstellt

| Punkt | Live-Zustand | Empfehlung | Ref |
|---|---|---|---|
| Monitoring auf dem DGX | `prometheus`, `grafana`, `dcgm-exporter` laufen mit | nicht mitdeployen — Monitoring gehört auf den separaten Server; DCGM lief ohnehin nie | D1 |
| `HF_HUB_OFFLINE` | nicht gesetzt (=0) → jeder Start braucht Internet + gültigen Token | nach dem ersten Download auf `1` setzen | D8 |
| Backups | keine — kein Cron, keine Timer | für den DGX vertretbar, der Zustand ist reproduzierbar | — |
| Transformers-Pin | ohne Commit-Pin | Commit pinnen | D9 |

**Kein Handlungsbedarf**, obwohl es zunächst wie eine Lücke aussieht: `ufw` ist
deaktiviert und Port 8000 lauscht auf `0.0.0.0`. Die Segmentierung erfolgt
zentral auf der **Palo Alto**; ein zweites Regelwerk auf dem Host ist nicht
gewollt.

---

## 9. Anbindung der Webserver-VM

Der DGX ist unter zwei internen Adressen erreichbar:

| Interface | Adresse | |
|---|---|---|
| `bond0` | `10.200.108.10` | Default-Route via `10.200.108.254` |
| `enP7s7` | `10.200.200.40` | zweites internes Netz |

Auf der Webserver-VM als `VLLM_ENDPOINT` konfiguriert. Zwei Dinge müssen stimmen:

```env
VLLM_ENDPOINT=http://10.200.108.10:8000/v1/
```

- **Trailing Slash `/v1/` ist zwingend.** Ohne ihn ersetzt der OpenAI-Client
  `/v1` per RFC 3986 durch den Endpoint-Pfad und vLLM antwortet 404
  (`DRIFT.md` D6).
- **Modellname in `litellm-config.yaml` ohne `google/`-Prefix:**
  `model: openai/gemma-4-26b-a4b-it` (`DRIFT.md` D5).

Welche Adresse real benutzt wird und was exakt in der `litellm-config.yaml` der
VM steht, ist von hier aus nicht feststellbar und im zweiten
Erfassungsschritt zu klären — siehe `webserver/README.md`.
