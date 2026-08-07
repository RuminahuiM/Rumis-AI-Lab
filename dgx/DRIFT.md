# DRIFT.md — Repo ↔ Live-System (DGX Spark)

Vergleich des **real laufenden Systems** auf `spark-753b` gegen den
bisherigen Repo-Stand `origin/claude/fork-new-setup-XOPpb`.

- **Erhebungsdatum:** 2026-08-07
- **Methode:** ausschliesslich lesend (`docker inspect`, `docker ps`,
  `nvidia-smi`, `ss -tlnp`, `systemctl`, `df -h`, `docker volume ls`)
- **Verbindliche Quelle:** die Compose-Labels der laufenden Container, nicht
  der Repo-Inhalt

## Rahmenbedingungen (Vorgabe Betrieb)

1. Auf dem DGX Spark läuft **ausschliesslich vLLM**. Monitoring läuft auf einem
   separaten Server.
2. Die Firewall wird **zentral auf der Palo Alto** geregelt, nicht auf dem Host.

---

## Live-Inventar

### Hardware / OS

| | |
|---|---|
| Hostname | `spark-753b` |
| Architektur | **aarch64 / arm64** |
| Kernel | `6.17.0-1014-nvidia` |
| GPU | 1× **NVIDIA GB10** |
| Treiber | **580.142**, CUDA 13.0 |
| Storage | `/dev/nvme0n1p2` — 3.7 TB, 113 GB belegt (4 %) |
| Docker | Engine **29.2.1**, Compose-Plugin **v5.0.2** |

### Netzwerk

| Interface | Adresse | |
|---|---|---|
| `bond0` | `10.200.108.10/24` | Default-Route via `10.200.108.254` |
| `enP7s7` | `10.200.200.40/24` | zweites internes Netz |

### Compose-Projekt

Alle laufenden Container tragen dieselben Labels:

```
com.docker.compose.project              = backend
com.docker.compose.project.working_dir  = /home/adm-dgx/Rumis-AI-Lab/backend
com.docker.compose.project.config_files = .../backend/docker-compose.yml
com.docker.compose.project.environment_file = (leer → Default backend/.env)
com.docker.compose.version              = 5.0.2
```

### Container

| Container | Image | Status | Port |
|---|---|---|---|
| `vllm` | `rumis-vllm:latest` (arm64, gebaut 2026-04-17) | Up 3 months, **healthy** | `0.0.0.0:8000` |
| `prometheus` | `prom/prometheus:latest` | Up 3 months | `0.0.0.0:9090` |
| `grafana` | `grafana/grafana:latest` | Up 3 months | `0.0.0.0:3000` |
| `dcgm-exporter` | `nvcr.io/nvidia/k8s/dcgm-exporter:latest` (**amd64**) | **Restarting (255)** | `127.0.0.1:9400` |

`vllm` erstellt am 2026-04-23 08:39 UTC, seither ununterbrochen.

### Laufender vLLM-Prozess

```
Entrypoint: ["vllm","serve"]
Cmd:        --model google/gemma-4-26b-a4b-it
            --served-model-name gemma-4-26b-a4b-it
            --max-model-len 8192
            --gpu-memory-utilization 0.90
            --tensor-parallel-size 1
            --host 0.0.0.0 --port 8000
Env:        HUGGING_FACE_HUB_TOKEN=<gesetzt>, HF_HUB_OFFLINE=0
Volume:     backend_huggingface_cache → /root/.cache/huggingface
```

Im Image: **vLLM 0.19.0**, **transformers 5.6.0.dev0**.
`GET /v1/models` liefert `id=gemma-4-26b-a4b-it`,
`root=google/gemma-4-26b-a4b-it`, `max_model_len=8192`.

### Volumes

`backend_huggingface_cache`, `backend_prometheus_data`, `backend_grafana_data`
— Präfix `backend_` durch den Compose-Projektnamen.

### systemd / Autostart

- `vllm.service`: **nicht installiert**, `/opt/rumis-ai-lab` existiert nicht
- `docker.service`: enabled + active
- Autostart faktisch über `restart: unless-stopped`

### Firewall

`ufw` installiert, aber `/etc/ufw/ufw.conf` → `ENABLED=no`; `nftables` inactive.
Port 8000 (sowie 9090, 3000) lauschen auf `0.0.0.0`. **So vorgesehen** — die
Segmentierung erfolgt auf der Palo Alto, ein zweites Regelwerk auf dem Host ist
nicht gewollt.

### Cron

Keine User-Crontab, in `/etc/cron.d/` nur Distro-Defaults. Keine Backups, keine
Wartungsjobs. Für den DGX vertretbar: der Zustand ist reproduzierbar (Modell aus
HuggingFace, Config aus diesem Repo).

---

## Abweichungen

Bewertung: **✅ Live ist richtig** · **📄 Repo ist richtig** · **❌ beides falsch**

---

### D1 — Monitoring läuft auf dem DGX, gehört aber nicht hierher ❌

| | |
|---|---|
| **Repo (XOPpb)** | nur Service `vllm` |
| **Live** | zusätzlich `prometheus`, `grafana`, `dcgm-exporter` + `monitoring/`-Configs, Grafana-Provisioning, vLLM-Dashboard, `MONITORING.md`, Volumes `prometheus_data`/`grafana_data` |
| **Soll** | nur vLLM; Monitoring auf separatem Server |

Der Stack läuft real — Prometheus scrapt vLLM erfolgreich über das Compose-Netz,
sichtbar als `GET /metrics` von `192.168.129.2` in den vLLM-Logs. Er ist beim
Go-Live mitgewachsen und inzwischen redundant.

**`dcgm-exporter` hat dabei nie funktioniert:** Das Image ist
`Architecture=amd64` (und von 2022), der Host ist aarch64 →
`exec /usr/local/dcgm/dcgm-exporter-entrypoint.sh: exec format error`,
**152 410 Restarts**. Das Prometheus-Target `dcgm` war permanent DOWN; es gab nie
GPU-Metriken (`DCGM_FI_DEV_*`), obwohl `MONITORING.md` sie dokumentierte.

**Einschätzung:** Hier ist **XOPpb näher am Soll**. Die drei Services samt
`monitoring/` und `MONITORING.md` sind deshalb **nicht** Teil von `dgx/`.
Falls GPU-Metriken gebraucht werden, gehören sie auf den Monitoring-Server —
dort scrapt Prometheus vLLM remote:

```yaml
scrape_configs:
  - job_name: vllm-dgx
    static_configs:
      - targets: ['10.200.108.10:8000']
```

**Offen auf dem Live-System:** die drei Container laufen weiter. Sie zu
entfernen ist eine Betriebsentscheidung und wurde hier nicht durchgeführt.
Der Crashloop ist reiner Ballast auf einem Host, der nur inferieren soll.

---

### D2 — `vllm.service` ist nicht installiert, und der Pfad im Unit war falsch ❌

| | |
|---|---|
| **Repo** | `backend/vllm.service` mit `WorkingDirectory=/opt/rumis-ai-lab/backend`; `docs/backend-setup.md` beschreibt `systemctl enable vllm` |
| **Live** | Unit nicht installiert, `/opt/rumis-ai-lab` existiert nicht. Autostart nur über `restart: unless-stopped` |

Der Unit hätte in dieser Form nicht funktioniert — das Deployment liegt in
`/home/adm-dgx/Rumis-AI-Lab/backend`.

**Einschätzung:** `restart: unless-stopped` + enabled `docker.service` übersteht
einen Reboot; genau deshalb ist der fehlende Unit nie aufgefallen. Da er live
nicht existiert und nicht gebraucht wird, ist er **nicht** Teil von `dgx/` —
statt eine Datei mitzuschleppen, die etwas verspricht, was nicht läuft,
dokumentiert `DEPLOYMENT.md` den real wirksamen Mechanismus.

---

### D3 — Live-Deployment läuft aus dem Git-Working-Tree ⚠️

| | |
|---|---|
| **Repo** | `/opt/rumis-ai-lab` (`docs/frontend-setup.md`, `vllm.service`) |
| **Live** | `/home/adm-dgx/Rumis-AI-Lab` — ein Git-Working-Tree, ausgecheckt auf `claude/docker-setup-guide-ARYXK`. Compose-Projektname daraus abgeleitet: `backend` |

**Einschätzung:** Funktioniert, hat aber eine gefährliche Eigenschaft:
Prometheus und Grafana binden Dateien aus `backend/monitoring/` ein, ein
`git checkout`/`git pull` verändert damit **laufende Bind-Mount-Quellen**.
Konkret würde ein Checkout dieses Branches dort `backend/` komplett entfernen.

Empfehlung: Deployment-Verzeichnis vom Git-Arbeitsverzeichnis trennen (Klon nach
`/opt/rumis-ai-lab`, oder `git worktree`). `dgx/docker-compose.yml` setzt den
Projektnamen deshalb explizit auf `rumis-dgx` — bewusst **nicht** `backend`,
damit ein Start aus `dgx/` nie mit dem laufenden Live-Projekt kollidiert.

---

### D4 — `--served-model-name` fehlte im Repo ✅

| | |
|---|---|
| **Repo (XOPpb)** | kein `--served-model-name` → vLLM würde als `google/gemma-4-26b-a4b-it` servieren |
| **Live** | `--served-model-name gemma-4-26b-a4b-it` |

**Einschätzung:** Live ist richtig und das ist die Kernanpassung des Go-Live
(Commits `0f1c6cb`, `c95809f`): der Slash in `google/…` bricht die
Modell-Auflösung in LiteLLM. Ohne das Flag ist der Stack Ende-zu-Ende kaputt.

---

### D5 — LiteLLM-Modell-ID (Webserver-Seite, hängt an D4) ✅

| | |
|---|---|
| **Repo (XOPpb)** | `litellm-config.yaml`: `model: openai/google/gemma-4-26b-a4b-it` |
| **Live-DGX** | serviert `gemma-4-26b-a4b-it` (ohne `google/`) |
| **Korrektur auf ARYXK** | `model: openai/gemma-4-26b-a4b-it` (Commit `c95809f`) |

**Einschätzung:** Die XOPpb-Variante passt nicht zum servierten Namen und würde
404 liefern; ARYXK ist richtig. **Auf der Webserver-VM zu verifizieren** — was
dort real steht, ist von hier aus nicht feststellbar.

---

### D6 — `VLLM_ENDPOINT`: Trailing Slash und Beispiel-IP ✅ / ❌

| | |
|---|---|
| **Repo (XOPpb)** | `VLLM_ENDPOINT=http://192.168.1.200:8000` |
| **Korrektur auf ARYXK** | `http://192.168.1.200:8000/v1/` — ohne Trailing Slash ersetzt der OpenAI-Client `/v1` per RFC 3986 durch den Endpoint-Pfad, vLLM antwortet 404 (Commit `9899833`) |
| **Live-DGX** | erreichbar unter `http://10.200.108.10:8000` bzw. `http://10.200.200.40:8000` |

**Einschätzung:** Der Trailing Slash ist zwingend. Die IP `192.168.1.200`
existiert in diesem Netz nirgends — ein Platzhalter, der wie ein echter Wert
aussieht. Welche der beiden DGX-Adressen die VM real benutzt, ist dort zu prüfen.

---

### D7 — `VLLM_QUANTIZATION` ist eine tote Variable ✅ / ❌

| | |
|---|---|
| **Repo** | `.env.example`: auskommentiert. `docs/backend-setup.md` behauptet dagegen, der Default sei „**with NVIDIA FP4 quantization**" |
| **Live** | `.env` **setzt** `VLLM_QUANTIZATION=modelopt_fp4`, aber die Compose-Datei liest die Variable nirgends → der Container hat **kein `--quantization`-Flag** |

Bewusste Entscheidung: Commit `b75a3fe` „drop quantization flag for Gemma 4
26B-A4B". Die Zeile in der Live-`.env` ist ein Rückstand davon.

**Einschätzung:** Das Verhalten (kein Flag) ist richtig — läuft seit 3 Monaten
healthy. Falsch sind die wirkungslose Zeile in der Live-`.env` und die
Doku-Aussage zu FP4. In `dgx/.env.example` ist die Variable mit explizitem
Hinweis erhalten, weil sie in der echten `.env` steht; sie kann dort
weggelassen werden, ohne dass sich etwas ändert.

---

### D8 — `HF_HUB_OFFLINE` ist live nicht gesetzt 📄

| | |
|---|---|
| **Repo** | Commit `4c68d68` führt die Variable ein: nach dem ersten Download auf `1` setzen |
| **Live** | in `.env` nicht gesetzt → Compose-Default `0` |

**Einschätzung:** Die Repo-Empfehlung ist richtig und wurde nie umgesetzt.
Mit `0` braucht jeder Container-Start Internet-Zugriff auf huggingface.co und
einen gültigen `HF_TOKEN` — ein abgelaufener Token oder eine Netzsperre
verhindert den Start, obwohl das Modell lokal im Volume liegt. Auf `1` zu setzen
macht den Start robust. (Änderung am Live-System, hier nicht durchgeführt.)

---

### D9 — Transformers wird ohne Pin aus dem Git-Master installiert ❌ (klein)

`Dockerfile`: `pip install git+https://github.com/huggingface/transformers.git`.
Im Live-Image steckt `5.6.0.dev0`. Ein Rebuild zu einem späteren Zeitpunkt
ergibt eine andere Version — das Image ist nicht reproduzierbar.

**Einschätzung:** Für exakte Reproduzierbarkeit den Commit pinnen. Solange das
laufende Image existiert, unkritisch; bei einem Neuaufbau kann es kippen.

---

### D10 — Preflight-Script prüft die Architektur nicht ❌ (klein)

`scripts/setup-dgx.sh` testet Treiber, Docker, Container Toolkit und GPU-Zugriff,
aber nicht, ob ein Image überhaupt arm64 ist. Genau daran ist DCGM gescheitert
(D1). Der Smoke-Test nutzt ausserdem `nvidia/cuda:12.4.0-base-ubuntu22.04`,
deutlich älter als der Live-Stack (Treiber 580.142 / CUDA 13.0).

**Einschätzung:** `docker image inspect --format '{{.Architecture}}'` in die
Checks aufnehmen — dieser Fehler wäre damit beim Deployment aufgefallen.

---

### D11 — Repo-Struktur mischte beide Tiers ✅ (organisatorisch, mit diesem Branch behoben)

Im Repo-Root lagen Webserver-Material (`docker-compose.yml`,
`litellm-config.yaml`, `nginx/`, `.env.example`) und DGX-Material (`backend/`)
nebeneinander, dazu `packer/` und `terraform/` für die Webserver-VM sowie
`docs/`, die beide Tiers vermischten.

**Einschätzung:** Auf diesem Branch ist der Root auf `dgx/` und `webserver/`
reduziert; alles nicht auf dem DGX Genutzte ist entfernt. Der bisherige Stand
bleibt in `claude/docker-setup-guide-ARYXK` und der Git-Historie erhalten. Die
Inhalte für `webserver/` werden im zweiten Schritt auf der VM erhoben.

---

## Zusammenfassung nach Dringlichkeit

| # | Thema | Bewertung |
|---|---|---|
| **D1** | Monitoring läuft auf dem DGX statt auf dem Monitoring-Server; DCGM zusätzlich im Dauer-Crashloop (152 410 Restarts) → alle drei Container abräumen | ❌ |
| **D4/D5/D6** | `--served-model-name`, LiteLLM-Modell-ID, `/v1/`-Trailing-Slash | ✅ Live richtig, XOPpb kaputt |
| **D2** | `vllm.service` nicht installiert, Pfad im Unit falsch | ❌ |
| **D3** | Deployment läuft aus dem Git-Working-Tree; Checkout bricht Bind-Mounts | ⚠️ |
| **D7** | `VLLM_QUANTIZATION` wirkungslos, Doku behauptet FP4 | Verhalten ✅, Doku ❌ |
| **D8** | `HF_HUB_OFFLINE` nie auf 1 gesetzt | 📄 Repo richtig |
| **D9/D10** | Transformers ohne Pin, Preflight prüft Architektur nicht | ❌ klein |
| **D11** | Repo-Struktur mischte beide Tiers | ✅ behoben |

**Nicht verändert:** Alle Feststellungen sind rein beobachtend. Es wurde kein
Container gestoppt, keine Live-Datei editiert, keine Unit installiert und keine
Firewall-Regel gesetzt. Insbesondere laufen die Monitoring-Container weiter,
obwohl D1 ihre Entfernung empfiehlt.
