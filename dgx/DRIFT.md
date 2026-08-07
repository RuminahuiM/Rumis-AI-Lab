# DRIFT.md — Repo ↔ Live-System (DGX Spark)

Vergleich des **real laufenden Systems** auf `spark-753b` gegen den Repo-Stand
`origin/claude/fork-new-setup-XOPpb` (Basis dieses Branches).

- **Erhebungsdatum:** 2026-08-07
- **Methode:** ausschliesslich lesend (`docker inspect`, `docker ps`,
  `nvidia-smi`, `ss -tlnp`, `systemctl`, `df -h`, `docker volume ls`). Am
  Live-System wurde nichts verändert.
- **Verbindliche Quelle:** die Compose-Labels der laufenden Container, nicht
  der Repo-Inhalt.

---

## 0. Live-Inventar (Ist-Zustand)

### Hardware / OS

| | |
|---|---|
| Hostname | `spark-753b` |
| Architektur | **aarch64 / arm64** |
| Kernel | `6.17.0-1014-nvidia` |
| GPU | 1× **NVIDIA GB10**, Persistence-Mode On |
| NVIDIA-Treiber | **580.142**, CUDA 13.0 |
| Storage | `/dev/nvme0n1p2` — 3.7 TB, 113 GB belegt (4 %), einzelne Partition auf `/` |
| RAM (shm) | `/dev/shm` 61 GB |
| Docker | Engine **29.2.1**, Compose-Plugin **v5.0.2** |

### Netzwerk

| Interface | Adresse | Rolle |
|---|---|---|
| `bond0` | `10.200.108.10/24` | Default-Route via `10.200.108.254` |
| `enP7s7` | `10.200.200.40/24` | zweites internes Netz |
| `wlP9s9` | — | DOWN |
| `docker0` | `192.168.128.1/24` | DOWN (ungenutzt) |
| `br-150dedc0b278` | `192.168.129.1/24` | Compose-Netz `backend_default` |

### Container (alle aus Compose-Projekt `backend`)

Alle vier Container tragen dieselben Labels:

```
com.docker.compose.project             = backend
com.docker.compose.project.working_dir = /home/adm-dgx/Rumis-AI-Lab/backend
com.docker.compose.project.config_files= /home/adm-dgx/Rumis-AI-Lab/backend/docker-compose.yml
com.docker.compose.project.environment_file = (leer — Default backend/.env)
com.docker.compose.version             = 5.0.2
```

| Container | Image | Status | Ports (Host) |
|---|---|---|---|
| `vllm` | `rumis-vllm:latest` (arm64, lokal gebaut 2026-04-17) | Up 3 months, **healthy** | `0.0.0.0:8000` + `[::]:8000` |
| `prometheus` | `prom/prometheus:latest` (arm64) | Up 3 months | `0.0.0.0:9090` |
| `grafana` | `grafana/grafana:latest` (arm64) | Up 3 months | `0.0.0.0:3000` |
| `dcgm-exporter` | `nvcr.io/nvidia/k8s/dcgm-exporter:latest` (**amd64**) | **Restarting (255)** | `127.0.0.1:9400` |

Container `vllm` erstellt am **2026-04-23 08:39 UTC**, seither ununterbrochen.

### Real laufender vLLM-Prozess

```
Entrypoint: ["vllm","serve"]
Cmd:        --model google/gemma-4-26b-a4b-it
            --served-model-name gemma-4-26b-a4b-it
            --max-model-len 8192
            --gpu-memory-utilization 0.90
            --tensor-parallel-size 1
            --host 0.0.0.0 --port 8000
Env:        HUGGING_FACE_HUB_TOKEN=<gesetzt>, HF_HUB_OFFLINE=0
Volume:     backend_huggingface_cache -> /root/.cache/huggingface
```

Im Image: **vLLM 0.19.0**, **transformers 5.6.0.dev0**.
`GET /v1/models` liefert live: `id=gemma-4-26b-a4b-it`,
`root=google/gemma-4-26b-a4b-it`, `max_model_len=8192`.

### Volumes

`backend_huggingface_cache`, `backend_prometheus_data`, `backend_grafana_data`
— alle vorhanden, Präfix `backend_` durch den Compose-Projektnamen.

### Firewall / Erreichbarkeit von Port 8000

- `ufw` ist installiert, aber in `/etc/ufw/ufw.conf` steht **`ENABLED=no`**.
- `nftables.service` ist **inactive**.
- `ss -tlnp`: Port 8000 lauscht auf **`0.0.0.0` und `[::]`**, ebenso 9090 und 3000.

**Port 8000 ist also host-seitig nicht eingeschränkt.** Dass der Dienst „nur
intern erreichbar" ist, ergibt sich allein aus der **Netz-Topologie**: der DGX
hat ausschliesslich private Adressen (`10.200.108.10`, `10.200.200.40`), keine
öffentliche IP und kein Port-Forwarding. Es ist **keine** Firewall-Regel, die
das absichert.

### systemd / Autostart

- `vllm.service`: **nicht installiert** (`Unit vllm.service could not be found`).
- `/etc/systemd/system/`: keine Rumis-/vLLM-Unit vorhanden.
- `/opt/rumis-ai-lab`: **existiert nicht**.
- `docker.service`: enabled + active.
- Autostart erfolgt faktisch über `restart: unless-stopped` in der Compose-Datei.

### Cron

`crontab -l` für `adm-dgx`: leer. `/etc/cron.d/`: nur Distro-Defaults
(`anacron`, `e2scrub_all`, `sysstat`). **Keine Backups, keine Wartungsjobs.**

---

## 1. Abweichungen

Bewertung: **✅ Live ist richtig** · **📄 Repo ist richtig** · **❌ beides falsch**

---

### D1 — `vllm.service` ist nicht installiert, und der Pfad im Unit ist falsch ❌

| | |
|---|---|
| **Repo** | `backend/vllm.service` mit `WorkingDirectory=/opt/rumis-ai-lab/backend`; `docs/backend-setup.md` beschreibt `systemctl enable vllm` |
| **Live** | Unit nicht installiert, `/opt/rumis-ai-lab` existiert nicht. Autostart nur über `restart: unless-stopped` |

Der Unit im Repo würde in dieser Form **nicht funktionieren** — das
Deployment liegt in `/home/adm-dgx/Rumis-AI-Lab/backend`, nicht in
`/opt/rumis-ai-lab/backend`.

**Einschätzung:** Beides ist unbefriedigend. `restart: unless-stopped` +
`docker.service enabled` überlebt einen Reboot und ist für dieses Lab
ausreichend — das ist der Grund, warum der fehlende Unit nie aufgefallen ist.
Empfehlung: Unit auf den echten Pfad korrigieren **und** installieren (dann ist
der Start explizit und `systemctl status` aussagekräftig), oder den Unit aus dem
Repo entfernen und die Doku auf `restart: unless-stopped` umstellen. Auf keinen
Fall so lassen: aktuell verspricht die Doku etwas, was nicht existiert.

---

### D2 — Deployment-Pfad: Repo-Working-Tree statt `/opt` ✅ (mit Vorbehalt)

| | |
|---|---|
| **Repo** | `/opt/rumis-ai-lab` (`docs/frontend-setup.md`, `vllm.service`) |
| **Live** | `/home/adm-dgx/Rumis-AI-Lab` — ein **Git-Working-Tree**, ausgecheckt auf Branch `claude/docker-setup-guide-ARYXK`. Compose-Projektname daraus abgeleitet: `backend` |

**Einschätzung:** Live ist der Ist-Zustand und funktioniert, hat aber eine
gefährliche Eigenschaft: Prometheus und Grafana binden Dateien aus
`backend/monitoring/` direkt ein. Ein `git checkout`/`git pull` in diesem
Verzeichnis verändert damit **laufende Bind-Mount-Quellen**. Konkret würde ein
Auschecken dieses Branches (`live/as-deployed`, Basis XOPpb) dort
`backend/monitoring/*` löschen und Grafana/Prometheus beim nächsten Restart
brechen. Empfehlung: Deployment-Verzeichnis vom Git-Arbeitsverzeichnis trennen
(Repo klonen nach `/opt/rumis-ai-lab`, oder `git worktree` benutzen).
Der Projektname sollte dann explizit gesetzt werden (`name: rumis-backend` in
der Compose-Datei), sonst ändern sich mit dem Verzeichnisnamen die
Volume-Namen (`backend_*`) und die Daten „verschwinden".

---

### D3 — Monitoring-Stack fehlt im Repo-Branch komplett ✅

| | |
|---|---|
| **Repo (XOPpb)** | nur Service `vllm`, ein Volume `huggingface_cache` |
| **Live** | zusätzlich `prometheus`, `grafana`, `dcgm-exporter` + Volumes `prometheus_data`, `grafana_data` + `monitoring/` (Prometheus-Config, Grafana-Provisioning, Dashboard) + `MONITORING.md` |

**Einschätzung:** Live ist richtig. Der Stack existiert real und wird benutzt
(Prometheus scrapt vLLM erfolgreich, sichtbar als `GET /metrics` von
`192.168.129.2` in den vLLM-Logs). Auf dem Branch
`claude/docker-setup-guide-ARYXK` ist er bereits vorhanden (Commit `59dfb85`) —
er fehlt nur in XOPpb. In `dgx/` dieses Branches ist er nun 1:1 enthalten.

---

### D4 — `VLLM_QUANTIZATION` ist eine toten Variable ✅ / 📄

| | |
|---|---|
| **Repo** | `.env.example`: auskommentiert, mit Hinweis „Add `--quantization` to docker-compose command if needed". `docs/backend-setup.md` behauptet dagegen, der Default sei „**with NVIDIA FP4 quantization**" und listet `VLLM_QUANTIZATION=modelopt_fp4` |
| **Live** | `.env` **setzt** `VLLM_QUANTIZATION=modelopt_fp4`, aber die Compose-Datei liest die Variable nirgends → der laufende Container hat **kein `--quantization`-Flag** |

Das war eine bewusste Entscheidung: Commit `b75a3fe` „fix(backend): drop
quantization flag for Gemma 4 26B-A4B". Die Zeile in der Live-`.env` ist ein
Rückstand davon.

**Einschätzung:** Das Verhalten (kein Quantization-Flag) ist richtig — es läuft
seit 3 Monaten stabil und healthy. Falsch sind zwei Dinge: die Zeile in der
Live-`.env` (wirkungslos, suggeriert aber FP4) und `docs/backend-setup.md`, das
FP4-Quantisierung behauptet. Beides bereinigen; die Variable entweder entfernen
oder in der Compose-Datei tatsächlich auswerten.

---

### D5 — `--served-model-name` fehlt in XOPpb ✅

| | |
|---|---|
| **Repo (XOPpb)** | kein `--served-model-name` → vLLM würde als `google/gemma-4-26b-a4b-it` servieren |
| **Live** | `--served-model-name gemma-4-26b-a4b-it`; `.env` hat `VLLM_SERVED_MODEL_NAME=gemma-4-26b-a4b-it` |

**Einschätzung:** Live ist richtig und ist die Kernanpassung des Go-Live
(Commits `0f1c6cb`, `c95809f`): der Slash in `google/…` bricht die
Modell-Auflösung in LiteLLM. Ohne dieses Flag ist der Stack Ende-zu-Ende kaputt.
Muss zwingend im Repo bleiben.

---

### D6 — DCGM-Exporter läuft seit dem ersten Tag nicht ❌ (wichtigster Fund)

| | |
|---|---|
| **Repo** | `nvcr.io/nvidia/k8s/dcgm-exporter:latest`, `MONITORING.md` dokumentiert `DCGM_FI_DEV_*`-Metriken als verfügbar |
| **Live** | **`Restarting (255)`, 152 410 Restarts.** Log: `exec /usr/local/dcgm/dcgm-exporter-entrypoint.sh: exec format error` |

Ursache: Das Image ist **`Architecture=amd64`** (und von 2022), der Host ist
**aarch64**. Der `:latest`-Tag dieses Repos ist kein Multi-Arch-Manifest — es
wurde ein x86-Image gezogen, das auf dem GB10 grundsätzlich nicht startbar ist.

Folgen:
- Prometheus-Target `dcgm` ist **permanent DOWN**.
- **Alle** GPU-Metriken aus `MONITORING.md` (`DCGM_FI_DEV_GPU_UTIL`,
  `DCGM_FI_DEV_FB_USED`, …) existieren nicht. Es gibt live **keine**
  GPU-Auslastungs-Überwachung, nur die vLLM-eigenen Metriken.
- 152 410 Restart-Zyklen erzeugen dauerhaft Log- und Scheduler-Last.

**Einschätzung:** Beide Varianten sind falsch — das Repo beschreibt einen
Zustand, der auf dieser Hardware nie erreichbar war. Optionen: einen arm64-
fähigen DCGM-Exporter pinnen (`nvcr.io/nvidia/k8s/dcgm-exporter:*-ubuntu22.04`
mit arm64-Manifest prüfen), oder den Service entfernen und die GPU-Metriken aus
`MONITORING.md` streichen. Bis dahin ist `MONITORING.md` in diesem Punkt
irreführend.

---

### D7 — Grafana-Dashboard zeigt per Default das falsche Modell 📄→❌

Das Dashboard `monitoring/grafana/provisioning/dashboards/vllm.json` (aus dem
vLLM-Upstream-Sample übernommen) hat als Default der Template-Variable
`model_name`:

```
/share/datasets/public_models/Meta-Llama-3-8B-Instruct
```

Live heisst das Modell `gemma-4-26b-a4b-it`. Alle Panels filtern auf
`model_name="$model_name"` und bleiben leer, bis die Variable manuell
umgestellt wird.

**Einschätzung:** Kosmetisch, aber es ist genau der Grund, warum ein Dashboard
„No data" zeigt, obwohl das Scraping funktioniert. Default auf den echten
`VLLM_SERVED_MODEL_NAME` setzen.

---

### D8 — LiteLLM-Modell-ID (Webserver-Seite, hängt an D5) ✅

| | |
|---|---|
| **Repo (XOPpb)** | `litellm-config.yaml`: `model: openai/google/gemma-4-26b-a4b-it` |
| **Live-DGX** | serviert `gemma-4-26b-a4b-it` (ohne `google/`) |
| **Korrektur auf ARYXK** | `model: openai/gemma-4-26b-a4b-it` (Commit `c95809f`) |

**Einschätzung:** Die XOPpb-Variante passt nicht zum live servierten Namen und
würde 404 liefern. Die ARYXK-Variante ist richtig. **Muss auf der Webserver-VM
verifiziert werden** — was dort real in `litellm-config.yaml` steht, ist von
hier aus nicht feststellbar.

---

### D9 — `VLLM_ENDPOINT`: Trailing Slash und falsche Beispiel-IP ✅ / ❌

| | |
|---|---|
| **Repo (XOPpb)** | `VLLM_ENDPOINT=http://192.168.1.200:8000` |
| **Korrektur auf ARYXK** | `http://192.168.1.200:8000/v1/` — ohne Trailing Slash ersetzt der OpenAI-Client `/v1` per RFC 3986 durch den Pfad und vLLM antwortet 404 (Commit `9899833`) |
| **Live-DGX** | erreichbar unter `http://10.200.108.10:8000` (bond0, Default-Route) bzw. `http://10.200.200.40:8000` (enP7s7) |

**Einschätzung:** Der Trailing Slash ist zwingend (ARYXK richtig). Die IP
`192.168.1.200` existiert in diesem Netz nirgends — sie ist ein Platzhalter, der
wie ein echter Wert aussieht. **Welche der beiden DGX-Adressen die Webserver-VM
real benutzt, muss auf der VM geprüft werden.**

---

### D10 — Keine Firewall auf dem DGX ❌

| | |
|---|---|
| **Repo** | Trifft für den DGX keine Aussage. `docs/troubleshooting.md` spricht nur über Ports auf der **VM** |
| **Live** | `ufw` installiert, aber `ENABLED=no`; `nftables` inactive; 8000, 9090, 3000 lauschen auf `0.0.0.0` |

**Einschätzung:** Beides ungenügend. Der Schutz ist rein topologisch (private
Netze, keine öffentliche IP) — es gibt keine explizite Regel, die z. B. Port
8000 auf die Webserver-VM einschränkt. Jeder Host in `10.200.108.0/24` oder
`10.200.200.0/24` kann das Modell ohne Authentisierung nutzen (vLLM selbst hat
keinen API-Key konfiguriert). Empfehlung: `ufw` mit expliziten Regeln aktivieren
(8000 nur von der Webserver-VM, 3000/9090 nur aus dem Admin-Netz) und im Repo
dokumentieren. **Achtung:** Das ist eine Änderung am Live-System und wurde hier
nicht durchgeführt.

---

### D11 — Grafana und Prometheus ohne Authentisierung öffentlich im internen Netz ❌

| | |
|---|---|
| **Repo = Live** | `GF_AUTH_ANONYMOUS_ENABLED=true`, `GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer`, `GF_SECURITY_ALLOW_EMBEDDING=true`, Port-Binding explizit `0.0.0.0:3000` bzw. `0.0.0.0:9090` |

Hier weichen Repo und Live nicht ab — die Konfiguration ist in beiden gleich.
Zusammen mit D10 heisst das aber: Grafana ist im gesamten internen Netz ohne
Login als Viewer offen, Prometheus (inkl. `/api/v1/query`) ganz ohne Schutz.

**Einschätzung:** Für ein Lab vertretbar, sollte aber bewusst entschieden und
dokumentiert sein, nicht als Nebenwirkung eines Copy-Paste-Defaults bestehen.

---

### D12 — `HF_HUB_OFFLINE` ist live nicht gesetzt 📄

| | |
|---|---|
| **Repo** | Commit `4c68d68` führt `HF_HUB_OFFLINE` ein, `.env.example` erklärt: nach dem ersten Download auf `1` setzen |
| **Live** | in `.env` **nicht** gesetzt → Compose-Default `0` → Container hat `HF_HUB_OFFLINE=0` |

**Einschätzung:** Die Repo-Empfehlung ist richtig und wurde live nie umgesetzt.
Solange `0` gilt, braucht jeder Container-Start Internet-Zugriff auf
huggingface.co und einen gültigen `HF_TOKEN` — ein abgelaufener Token oder eine
Netzsperre verhindert dann den Start, obwohl das Modell lokal im Volume liegt.
Auf `1` zu setzen macht den Start robust. (Änderung am Live-System — hier nicht
durchgeführt.)

---

### D13 — Preflight-Script und Doku nennen inkonsistente CUDA-Test-Images ❌ (klein)

| | |
|---|---|
| `scripts/setup-dgx.sh` | Smoke-Test mit `nvidia/cuda:12.4.0-base-ubuntu22.04` |
| `MONITORING.md` | Troubleshooting mit `nvidia/cuda:12.0.0-base-ubuntu22.04` |
| **Live** | Treiber 580.142 / CUDA 13.0, Host arm64 |

**Einschätzung:** Zwei verschiedene Tags für denselben Zweck, beide deutlich
älter als der Live-Stack. Angesichts von D6 (amd64-Image auf arm64) sollte der
Smoke-Test ausserdem explizit die Architektur prüfen — genau dieser Fehler wäre
damit beim Deployment aufgefallen. Auf ein Tag vereinheitlichen und
`docker image inspect --format '{{.Architecture}}'` in die Checks aufnehmen.

---

### D14 — Repo enthält keinerlei Backup/Retention-Konzept ❌ (klein)

| | |
|---|---|
| **Live** | kein Cron, keine systemd-Timer. Prometheus-Retention 30 d; `grafana_data` und `prometheus_data` liegen unbesichert in Docker-Volumes |
| **Repo** | keine Aussage |

**Einschätzung:** Für den DGX unkritisch — der Zustand ist reproduzierbar
(Modell aus HF, Dashboards aus dem Provisioning). Sollte aber bewusst als
„bewusst kein Backup" dokumentiert sein. Die wirklich schützenswerten Daten
(n8n-Workflows, Open-WebUI-Chats) liegen auf der Webserver-VM und sind dort zu
prüfen.

---

### D15 — Packer/Terraform/VMDK betreffen nicht den DGX ✅ (organisatorisch)

`packer/`, `terraform/` und die VMDK-/vSphere-Beschreibungen provisionieren die
**Webserver-VM**, nicht den DGX. Der DGX wurde manuell aufgesetzt: eine einzige
NVMe (`/dev/nvme0n1p2`, 3.7 TB, 113 GB belegt), keine separate Datenpartition,
HF-Cache im Docker-Volume `backend_huggingface_cache`.

**Einschätzung:** Kein Widerspruch, aber irreführende Ordnerstruktur — im
Repo-Root liegt Webserver-Material neben DGX-Material. Genau das adressiert die
neue Trennung `dgx/` ↔ `webserver/`.

---

### D16 — `docs/backend-setup.md`: Test-Request würde live fehlschlagen ✅ (klein, Folge von D5)

Der dokumentierte Test-Call verwendet `"model": "google/gemma-4-26b-a4b-it"`.
Live ist der gültige Name `gemma-4-26b-a4b-it`; mit dem `google/`-Prefix
antwortet vLLM mit „model not found".

**Einschätzung:** Doku nachziehen — sonst schlägt die erste Verifikation nach
einem Redeployment fehl und sieht wie ein Deployment-Fehler aus.

---

### D17 — Verzeichnis-Duplikat `backend/` ↔ `dgx/` (durch diesen Branch neu)

Auf diesem Branch existiert der DGX-Stand jetzt zweimal: als historisches
`backend/` (aus XOPpb) und als `dgx/` (Live-Abbild). Das ist bewusst so —
Aufräumen war für diesen Schritt ausdrücklich ausgeklammert.

**Einschätzung:** Vor einem Merge auflösen: `backend/` entfernen, `dgx/` ist die
Wahrheit. **Vorher D2 beachten** — solange das Live-Deployment aus
`backend/` läuft, darf dieser Branch nicht in `/home/adm-dgx/Rumis-AI-Lab`
ausgecheckt werden.

---

## 2. Zusammenfassung nach Dringlichkeit

| # | Thema | Bewertung |
|---|---|---|
| **D6** | DCGM-Exporter: amd64-Image auf arm64, 152 410 Restarts, keine GPU-Metriken | ❌ beides falsch |
| **D1** | `vllm.service` nicht installiert, Pfad im Unit falsch | ❌ beides falsch |
| **D2** | Live-Deployment läuft aus dem Git-Working-Tree; `checkout` bricht Bind-Mounts | ⚠️ funktioniert, riskant |
| **D10/D11** | Keine Firewall; Grafana/Prometheus/vLLM ohne Auth im internen Netz | ❌ beides falsch |
| **D5/D8/D9** | `--served-model-name`, LiteLLM-Modell-ID, `/v1/`-Trailing-Slash | ✅ Live richtig, XOPpb kaputt |
| **D3** | Monitoring-Stack fehlt in XOPpb | ✅ Live richtig |
| **D4** | `VLLM_QUANTIZATION` wirkungslos, Doku behauptet FP4 | Verhalten ✅, Doku ❌ |
| **D12** | `HF_HUB_OFFLINE` nie auf 1 gesetzt | 📄 Repo richtig |
| **D7/D13/D14/D16** | Dashboard-Default, CUDA-Tags, kein Backup, falscher Test-Call | ❌ klein |

**Nicht verändert:** Alle Feststellungen sind rein beobachtend. Es wurde kein
Container gestoppt, keine Live-Datei editiert, keine Unit installiert und keine
Firewall-Regel gesetzt.
