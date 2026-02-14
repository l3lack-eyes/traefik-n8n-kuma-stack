#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="/root/stack"
DOMAIN="steamchi.online"
N8N_HOST="n8n.${DOMAIN}"
KUMA_HOST="status.${DOMAIN}"

echo "==> Traefik + Cloudflare DNS-01 + n8n + Uptime Kuma (8443) installer"
echo

read -rp "ACME email (Let's Encrypt): " ACME_EMAIL
read -rsp "Cloudflare DNS API Token: " CF_TOKEN
echo

read -rp "Timezone (default: Europe/Berlin): " TZ_INPUT || true
TZ="${TZ_INPUT:-Asia/Tehran}"

echo "==> Creating stack directory at ${STACK_DIR}"
mkdir -p "${STACK_DIR}"
cd "${STACK_DIR}"

echo "==> Writing docker-compose.yml"
cat > docker-compose.yml <<'YAML'
networks:
  proxy:
    name: proxy

services:
  traefik:
    image: traefik:v3.1
    container_name: traefik
    restart: unless-stopped
    command:
      - --providers.file.directory=/etc/traefik/dynamic
      - --providers.file.watch=true
      - --entrypoints.websecure.address=:8443
      - --certificatesresolvers.le.acme.email=${ACME_EMAIL}
      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.le.acme.dnschallenge=true
      - --certificatesresolvers.le.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.le.acme.dnschallenge.delaybeforecheck=10
      - --log.level=INFO
      - --accesslog=false
      - --global.checknewversion=false
      - --global.sendanonymoususage=false
    ports:
      - "8443:8443"
    environment:
      - TZ=${TZ}
      - CLOUDFLARE_DNS_API_TOKEN=${CLOUDFLARE_DNS_API_TOKEN}
    volumes:
      - ./traefik/dynamic.yml:/etc/traefik/dynamic/dynamic.yml:ro
      - ./letsencrypt:/letsencrypt
    networks:
      - proxy
    mem_limit: 220m

  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    volumes:
      - kuma_data:/app/data
    networks:
      - proxy
    expose:
      - "3001"
    mem_limit: 300m

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    environment:
      - TZ=${TZ}
      - DB_TYPE=sqlite
      - DB_SQLITE_VACUUM_ON_STARTUP=true
      - N8N_USER_FOLDER=/home/node/.n8n
      - N8N_HOST=${N8N_HOST}
      - N8N_PROTOCOL=https
      - N8N_PORT=5678
      - WEBHOOK_URL=https://${N8N_HOST}:8443/
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168
      - N8N_LOG_LEVEL=warn
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - proxy
    expose:
      - "5678"
    mem_limit: 1100m

volumes:
  kuma_data:
  n8n_data:
YAML

echo "==> Writing traefik/dynamic.yml"
mkdir -p traefik
cat > traefik/dynamic.yml <<YAML
http:
  routers:
    kuma:
      rule: "Host(\`${KUMA_HOST}\`)"
      entryPoints:
        - websecure
      tls:
        certResolver: le
      service: kuma_svc

    n8n:
      rule: "Host(\`${N8N_HOST}\`)"
      entryPoints:
        - websecure
      tls:
        certResolver: le
      service: n8n_svc

  services:
    kuma_svc:
      loadBalancer:
        servers:
          - url: "http://uptime-kuma:3001"

    n8n_svc:
      loadBalancer:
        servers:
          - url: "http://n8n:5678"
YAML

echo "==> Writing .env"
cat > .env <<ENV
ACME_EMAIL=${ACME_EMAIL}
CLOUDFLARE_DNS_API_TOKEN=${CF_TOKEN}
TZ=${TZ}
N8N_HOST=${N8N_HOST}
ENV

echo "==> Preparing letsencrypt/acme.json (permissions matter)"
rm -rf ./letsencrypt
mkdir -p ./letsencrypt
touch ./letsencrypt/acme.json
chmod 600 ./letsencrypt/acme.json

echo "==> Starting stack"
docker compose down || true
docker compose up -d

echo
echo "==> Done."
echo "Logs:"
echo "  docker compose logs -f --tail=200 traefik"
echo
echo "URLs:"
echo "  https://${KUMA_HOST}:8443"
echo "  https://${N8N_HOST}:8443"
