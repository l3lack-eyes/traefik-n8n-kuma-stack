#!/usr/bin/env bash
set -euo pipefail

# ---- Must be root ----
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Run as root with:"
  echo "  curl -Ls https://raw.githubusercontent.com/l3lack-eyes/traefik-n8n-kuma-stack/main/install_stack.sh | sudo bash"
  exit 1
fi

# ---- Helpers ----
need_cmd() { command -v "$1" >/dev/null 2>&1; }

prompt() { # prompt "Text" varname [silent]
  local text="$1"
  local var="$2"
  local silent="${3:-0}"
  local val=""
  while true; do
    if [ "$silent" = "1" ]; then
      read -rsp "$text" val </dev/tty || true
      echo
    else
      read -rp "$text" val </dev/tty || true
    fi
    if [ -n "${val}" ]; then
      printf -v "$var" '%s' "$val"
      return 0
    fi
    echo "Value cannot be empty. Try again."
  done
}

# ---- Base deps ----
export DEBIAN_FRONTEND=noninteractive

if ! need_cmd apt-get; then
  echo "ERROR: This installer currently supports Debian/Ubuntu systems (apt-get not found)."
  exit 1
fi

apt-get update -y >/dev/null 2>&1 || true
apt-get install -y ca-certificates curl gnupg >/dev/null 2>&1 || true

if ! need_cmd git; then
  echo "==> Installing git..."
  apt-get update -y
  apt-get install -y git
fi

# ---- Install Docker if missing ----
if ! need_cmd docker; then
  echo "==> Docker not found. Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker || true
else
  echo "==> Docker already installed."
fi

# ---- Install Docker Compose plugin if missing ----
if ! docker compose version >/dev/null 2>&1; then
  echo "==> Installing docker compose plugin..."
  apt-get update -y
  apt-get install -y docker-compose-plugin
else
  echo "==> Docker compose plugin already available."
fi

# ---- Config ----
STACK_DIR="/root/stack"
DOMAIN="steamchi.online"
N8N_HOST="n8n.${DOMAIN}"
KUMA_HOST="status.${DOMAIN}"
WZML_HOST="wzml.${DOMAIN}"

echo
echo "==> Traefik + Cloudflare DNS-01 + n8n + Uptime Kuma + WZML (HTTPS on :8443)"
echo

prompt "ACME email (Let's Encrypt): " ACME_EMAIL 0
prompt "Cloudflare DNS API Token: " CF_TOKEN 1
read -rp "Timezone (default: Europe/Berlin): " TZ_INPUT </dev/tty || true
TZ="${TZ_INPUT:-Europe/Berlin}"

# ---- WZML repo (wzv3 HEAD) ----
echo "==> Preparing WZML repo (wzv3 HEAD)..."
WZML_DIR="/root/wzml/WZML-X"
if [ ! -d "$WZML_DIR/.git" ]; then
  mkdir -p /root/wzml
  git clone https://github.com/SilentDemonSD/WZML-X.git "$WZML_DIR"
fi
cd "$WZML_DIR"
git fetch --all
git checkout wzv3
git pull origin wzv3
cd /root

# ---- Your config.py must exist ----
if [ ! -f /root/config.py ]; then
  echo "ERROR: /root/config.py not found."
  echo "Create it first:"
  echo "  nano /root/config.py"
  exit 1
fi

# ---- Write stack ----
echo "==> Creating stack directory at ${STACK_DIR}"
mkdir -p "${STACK_DIR}"
cd "${STACK_DIR}"

echo "==> Writing docker-compose.yml"
cat > docker-compose.yml <<YAML
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
      - --certificatesresolvers.le.acme.email=\${ACME_EMAIL}
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
      - TZ=\${TZ}
      - CLOUDFLARE_DNS_API_TOKEN=\${CLOUDFLARE_DNS_API_TOKEN}
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
      - TZ=\${TZ}
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

  wzml:
    build:
      context: /root/wzml/WZML-X
      dockerfile: Dockerfile
    container_name: wzml
    restart: unless-stopped
    command: bash start.sh
    expose:
      - "5000"
    volumes:
      - /root/config.py:/app/config.py:ro
    working_dir: /app
    networks:
      - proxy
    mem_limit: 400m

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
      entryPoints: [websecure]
      tls: { certResolver: le }
      service: kuma_svc

    n8n:
      rule: "Host(\`${N8N_HOST}\`)"
      entryPoints: [websecure]
      tls: { certResolver: le }
      service: n8n_svc

    wzml:
      rule: "Host(\`${WZML_HOST}\`)"
      entryPoints: [websecure]
      tls: { certResolver: le }
      service: wzml_svc

  services:
    kuma_svc:
      loadBalancer:
        servers:
          - url: "http://uptime-kuma:3001"

    n8n_svc:
      loadBalancer:
        servers:
          - url: "http://n8n:5678"

    wzml_svc:
      loadBalancer:
        servers:
          - url: "http://wzml:5000"
YAML

echo "==> Writing .env"
cat > .env <<ENV
ACME_EMAIL=${ACME_EMAIL}
CLOUDFLARE_DNS_API_TOKEN=${CF_TOKEN}
TZ=${TZ}
ENV

echo "==> Preparing letsencrypt/acme.json"
rm -rf ./letsencrypt
mkdir -p ./letsencrypt
touch ./letsencrypt/acme.json
chmod 600 ./letsencrypt/acme.json

echo "==> Starting stack (build included for WZML)"
docker compose down --remove-orphans >/dev/null 2>&1 || true
docker compose up -d --build

echo
echo "==> Done."
echo "URLs:"
echo "  https://${KUMA_HOST}:8443"
echo "  https://${N8N_HOST}:8443"
echo "  https://${WZML_HOST}:8443"
echo
echo "Logs:"
echo "  cd /root/stack && docker compose logs -f --tail=200 traefik"
