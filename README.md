# Traefik + Cloudflare DNS-01 + n8n + Uptime Kuma (HTTPS on 8443)

This project deploys:

- Traefik reverse proxy
- Automatic SSL via Let's Encrypt + Cloudflare DNS challenge
- n8n automation platform
- Uptime Kuma monitoring dashboard

## Domains

- https://status.example.com:8443
- https://n8n.example.com:8443

## Install

```bash
bash <(curl -Ls https://raw.githubusercontent.com/l3lack-eyes/traefik-n8n-kuma-stack/main/install_stack.sh)
```
