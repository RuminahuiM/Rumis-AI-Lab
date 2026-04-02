#!/usr/bin/env bash
# =============================================================================
# init-ssl.sh – Bootstrap Let's Encrypt SSL for Rumis AI Lab
#
# Run ONCE on first deployment after DNS is pointed at this server.
# After this script completes, certbot auto-renews every 12 h.
#
# Usage:
#   bash scripts/init-ssl.sh
# =============================================================================
set -euo pipefail

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ -f ".env" ]]; then
  set -a; source .env; set +a
fi

OUI_DOMAIN="${OUI_DOMAIN:?'OUI_DOMAIN is not set. Add it to your .env file (e.g. OUI_DOMAIN=oui.mydomain.ch)'}"
OC_DOMAIN="${OC_DOMAIN:?'OC_DOMAIN is not set. Add it to your .env file (e.g. OC_DOMAIN=oc.mydomain.ch)'}"
N8N_DOMAIN="${N8N_DOMAIN:?'N8N_DOMAIN is not set. Add it to your .env file (e.g. N8N_DOMAIN=n8n.mydomain.ch)'}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:?'CERTBOT_EMAIL is not set. Add it to your .env file (e.g. CERTBOT_EMAIL=you@example.com)'}"
OC_AUTH_USER="${OC_AUTH_USER:?'OC_AUTH_USER is not set. Add it to your .env file (e.g. OC_AUTH_USER=admin)'}"
OC_AUTH_PASSWORD="${OC_AUTH_PASSWORD:?'OC_AUTH_PASSWORD is not set. Add it to your .env file (e.g. OC_AUTH_PASSWORD=yourpassword)'}"

echo "==========================================================================
  Rumis AI Lab – SSL bootstrap
  Open WebUI : https://${OUI_DOMAIN}
  OpenClaw   : https://${OC_DOMAIN}
  n8n        : https://${N8N_DOMAIN}
  Email      : ${CERTBOT_EMAIL}
=========================================================================="

# ── Ensure directories exist ──────────────────────────────────────────────────
mkdir -p nginx/conf.d nginx/auth certbot/www certbot/conf
mkdir -p openclaw/config openclaw/workspace
# OpenClaw runs as uid 1000 (node user) — fix ownership so it can write config.
chown -R 1000:1000 openclaw/ 2>/dev/null || true

# ── OpenClaw gateway config (needed for non-loopback binding in Docker) ───────
# Without this, openclaw refuses to start when --bind lan is set.
# See: https://github.com/openclaw/openclaw/issues/25009
if [[ ! -f "openclaw/config/settings.json" ]]; then
  echo "   Writing OpenClaw gateway config (controlUi origin fallback)..."
  cat > openclaw/config/settings.json <<'OCJSON'
{
  "gateway": {
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true
    }
  }
}
OCJSON
  chown 1000:1000 openclaw/config/settings.json 2>/dev/null || true
fi

# ── Generate OpenClaw htpasswd (nginx basic auth) ─────────────────────────────
echo "   Generating OpenClaw basic-auth credentials..."
HASH=$(openssl passwd -apr1 "${OC_AUTH_PASSWORD}")
printf '%s:%s\n' "${OC_AUTH_USER}" "${HASH}" > nginx/auth/openclaw.htpasswd
chmod 600 nginx/auth/openclaw.htpasswd
echo "   htpasswd written to nginx/auth/openclaw.htpasswd (user: ${OC_AUTH_USER})"

# ── Step 1: write HTTP-only nginx config (needed for ACME challenge) ──────────
echo ""
echo "── Step 1/4: Writing HTTP-only nginx config..."

cat > nginx/conf.d/app.conf <<NGINX
# HTTP – Let's Encrypt ACME challenge + temporary 503
server {
    listen 80;
    server_name ${OUI_DOMAIN} ${OC_DOMAIN} ${N8N_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        return 503 "SSL setup in progress…\n";
        add_header Content-Type text/plain;
    }
}
NGINX

# ── Step 2: start / reload nginx so certbot can reach the ACME endpoint ───────
echo ""
echo "── Step 2/4: Starting nginx..."
docker compose up -d --no-deps nginx
echo "   Waiting 5 s for nginx to be ready..."
sleep 5

# ── Step 3: obtain certificates ───────────────────────────────────────────────
echo ""
echo "── Step 3/4: Requesting certificate for ${OUI_DOMAIN}..."
docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email "${CERTBOT_EMAIL}" \
  --agree-tos \
  --no-eff-email \
  --keep-until-expiring \
  -d "${OUI_DOMAIN}"

echo ""
echo "── Step 3/4: Requesting certificate for ${OC_DOMAIN}..."
docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email "${CERTBOT_EMAIL}" \
  --agree-tos \
  --no-eff-email \
  -d "${OC_DOMAIN}"

echo ""
echo "── Step 3/4: Requesting certificate for ${N8N_DOMAIN}..."
docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email "${CERTBOT_EMAIL}" \
  --agree-tos \
  --no-eff-email \
  -d "${N8N_DOMAIN}"

# ── Step 4: write full HTTPS nginx config and reload ─────────────────────────
echo ""
echo "── Step 4/4: Writing HTTPS nginx config and reloading..."

# Download recommended SSL options from certbot (idempotent)
SSL_OPTS="certbot/conf/options-ssl-nginx.conf"
if [[ ! -f "${SSL_OPTS}" ]]; then
  curl -fsSL \
    "https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf" \
    -o "${SSL_OPTS}" 2>/dev/null || \
  cat > "${SSL_OPTS}" <<'EOF'
ssl_session_cache    shared:le_nginx_SSL:10m;
ssl_session_timeout  1440m;
ssl_session_tickets  off;
ssl_protocols        TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256";
EOF
fi

DH_PARAMS="certbot/conf/ssl-dhparams.pem"
if [[ ! -f "${DH_PARAMS}" ]]; then
  echo "   Generating DH params (this takes ~30 s)..."
  openssl dhparam -out "${DH_PARAMS}" 2048 2>/dev/null
fi

cat > nginx/conf.d/app.conf <<NGINX
# =============================================================================
# Rumis AI Lab – Nginx reverse proxy  (generated by scripts/init-ssl.sh)
# =============================================================================

# Hide nginx version from Server response header
server_tokens off;

# WebSocket upgrade map – sends Connection: upgrade for WS, close for plain HTTP
map \$http_upgrade \$connection_upgrade {
    default  upgrade;
    ''       close;
}

# ── HTTP → HTTPS redirect + Let's Encrypt renewal challenge ──────────────────
server {
    listen 80;
    server_name ${OUI_DOMAIN} ${OC_DOMAIN} ${N8N_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# ── Open WebUI  →  https://${OUI_DOMAIN} ─────────────────────────────────────
server {
    listen 443 ssl;
    http2 on;
    server_name ${OUI_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${OUI_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${OUI_DOMAIN}/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options           "SAMEORIGIN"   always;
    add_header X-Content-Type-Options    "nosniff"      always;
    add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
    # CSP: allows Open WebUI's inline scripts/styles, WebSockets, blobs, and images from anywhere.
    # unsafe-inline/eval are required by the Open WebUI SPA.
    add_header Content-Security-Policy   "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https:; connect-src 'self' wss: https: ws:; font-src 'self' data:; worker-src 'self' blob:; media-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'self';" always;

    # Allow uploads up to 100 MB (documents, images). Raise if you need larger files.
    client_max_body_size 100M;

    location / {
        proxy_pass         http://open-webui:8080;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;

        # Disable buffering – required for LLM token streaming (SSE)
        proxy_buffering    off;

        # WebSocket support (required by Open WebUI)
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection \$connection_upgrade;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}

# ── OpenClaw  →  https://${OC_DOMAIN} ────────────────────────────────────────
server {
    listen 443 ssl;
    http2 on;
    server_name ${OC_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${OC_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${OC_DOMAIN}/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options           "SAMEORIGIN"   always;
    add_header X-Content-Type-Options    "nosniff"      always;
    add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy   "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https:; connect-src 'self' wss: https: ws:; font-src 'self' data:; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'self';" always;

    client_max_body_size 20M;

    # Basic auth – first line of defence before OpenClaw's own token auth.
    # Credentials set via OC_AUTH_USER / OC_AUTH_PASSWORD in .env.
    auth_basic           "OpenClaw";
    auth_basic_user_file /etc/nginx/auth/openclaw.htpasswd;

    location / {
        proxy_pass         http://openclaw-gateway:18789;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;

        # Disable buffering – required for streaming responses
        proxy_buffering    off;

        # WebSocket support (required by OpenClaw)
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection \$connection_upgrade;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}

# ── n8n  →  https://${N8N_DOMAIN} ────────────────────────────────────────────
server {
    listen 443 ssl;
    http2 on;
    server_name ${N8N_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${N8N_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${N8N_DOMAIN}/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options           "SAMEORIGIN"   always;
    add_header X-Content-Type-Options    "nosniff"      always;
    add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
    # n8n requires unsafe-inline/eval for its editor UI and WebSocket connections.
    add_header Content-Security-Policy   "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https:; connect-src 'self' wss: https: ws:; font-src 'self' data:; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'self';" always;

    # Allow larger payloads for workflow imports and binary data
    client_max_body_size 50M;

    location / {
        proxy_pass         http://n8n:5678;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;

        # Disable buffering – required for n8n SSE and workflow streaming
        proxy_buffering    off;

        # WebSocket support (required by n8n editor)
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection \$connection_upgrade;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
NGINX

echo "   Stopping nginx (full stack starts via 'docker compose up -d' next)..."
docker compose stop nginx

echo ""
echo "=========================================================================="
echo "  SSL setup complete!"
echo ""
echo "  Open WebUI  →  https://${OUI_DOMAIN}"
echo "  OpenClaw    →  https://${OC_DOMAIN}"
echo "  n8n         →  https://${N8N_DOMAIN}"
echo ""
echo "  Certificates auto-renew every 12 h via the certbot container."
echo "=========================================================================="
