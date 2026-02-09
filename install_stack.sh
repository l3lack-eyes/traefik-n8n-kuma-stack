#!usrbinenv bash
set -euo pipefail

STACK_DIR=rootstack
DOMAIN=steamchi.online
N8N_HOST=n8n.${DOMAIN}
KUMA_HOST=status.${DOMAIN}

echo == Traefik + Cloudflare DNS-01 + n8n + Uptime Kuma (8443) installer
echo

# ---- Collect inputs ----
read -rp ACME email (Let's Encrypt)  ACME_EMAIL
read -rsp Cloudflare DNS API Token  CF_TOKEN
echo

# Optional timezone
read -rp Timezone (default EuropeBerlin)  TZ_INPUT  true
TZ=${TZ_INPUT-EuropeBerlin}

echo == Creating stack directory at ${STACK_DIR}
mkdir -p ${STACK_DIR}
cd ${STACK_DIR}

echo == Writing docker-compose.yml
cat  docker-compose.yml 'YAML'
networks
  proxy
    name proxy

services
  traefik
    image traefikv3.1
    container_name traefik
    restart unless-stopped
    command
      # IMPORTANT file provider (no docker socket; works with old docker API)
      - --providers.file.directory=etctraefikdynamic
      - --providers.file.watch=true

      # HTTPS only on 8443
      - --entrypoints.websecure.address=8443

      # Let's Encrypt via DNS-01 (Cloudflare)
      - --certificatesresolvers.le.acme.email=${ACME_EMAIL}
      - --certificatesresolvers.le.acme.storage=letsencryptacme.json
      - --certificatesresolvers.le.acme.dnschallenge=true
      - --certificatesresolvers.le.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.le.acme.dnschallenge.delaybeforecheck=10

      # Logs (INFO helpful for first run; you can change to WARN later)
      - --log.level=INFO
      - --accesslog=false
      - --global.checknewversion=false
      - --global.sendanonymoususage=false
    ports
      - 84438443
    environment
      - TZ=${TZ}
      - CLOUDFLARE_DNS_API_TOKEN=${CLOUDFLARE_DNS_API_TOKEN}
    volumes
      - .traefikdynamic.ymletctraefikdynamicdynamic.ymlro
      - .letsencryptletsencrypt
    networks
      - proxy
    mem_limit 220m

  uptime-kuma
    image louislamuptime-kuma1
    container_name uptime-kuma
    restart unless-stopped
    volumes
      - kuma_dataappdata
    networks
      - proxy
    expose
      - 3001
    mem_limit 300m

  n8n
    image n8nion8nlatest
    container_name n8n
    restart unless-stopped
    environment
      - TZ=${TZ}

      # Low-RAM DB SQLite
      - DB_TYPE=sqlite
      - DB_SQLITE_VACUUM_ON_STARTUP=true
      - N8N_USER_FOLDER=homenode.n8n

      # n8n internal port MUST stay 5678 (Traefik routes to it)
      - N8N_HOST=${N8N_HOST}
      - N8N_PROTOCOL=https
      - N8N_PORT=5678
      - WEBHOOK_URL=https${N8N_HOST}8443

      # Reduce stored execution data
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168
      - N8N_LOG_LEVEL=warn
    volumes
      - n8n_datahomenode.n8n
    networks
      - proxy
    expose
      - 5678
    mem_limit 1100m

volumes
  kuma_data
  n8n_data
YAML

echo == Writing traefikdynamic.yml
mkdir -p traefik
cat  traefikdynamic.yml YAML
http
  routers
    kuma
      rule Host(`${KUMA_HOST}`)
      entryPoints
        - websecure
      tls
        certResolver le
      service kuma_svc

    n8n
      rule Host(`${N8N_HOST}`)
      entryPoints
        - websecure
      tls
        certResolver le
      service n8n_svc

  services
    kuma_svc
      loadBalancer
        servers
          - url httpuptime-kuma3001

    n8n_svc
      loadBalancer
        servers
          - url httpn8n5678
YAML

echo == Writing .env
cat  .env ENV
ACME_EMAIL=${ACME_EMAIL}
CLOUDFLARE_DNS_API_TOKEN=${CF_TOKEN}
TZ=${TZ}
N8N_HOST=${N8N_HOST}
ENV

echo == Preparing letsencryptacme.json (permissions matter)
rm -rf letsencrypt
mkdir -p letsencrypt
touch letsencryptacme.json
chmod 600 letsencryptacme.json

echo == Starting stack
docker compose down  true
docker compose up -d

echo
echo == Done.
echo Next checks
echo   1) Make sure firewallprovider allows TCP 8443.
echo   2) Make sure Cloudflare DNS A records exist
echo        - ${KUMA_HOST} - your server IP
echo        - ${N8N_HOST}  - your server IP
echo
echo Logs
echo   docker compose logs -f --tail=200 traefik
echo
echo URLs
echo   https${KUMA_HOST}8443
echo   https${N8N_HOST}8443
