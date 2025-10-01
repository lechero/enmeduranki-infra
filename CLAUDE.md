# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a multi-server infrastructure repository for managing Docker-based deployments with Traefik reverse proxy. The architecture uses a template-based approach where `templates/server/` contains reusable configurations that are copied to individual server directories under `servers/` and customized per deployment.

## Repository Structure

- **`templates/server/`** - Template configurations for new server setups
  - `proxy/` - Traefik reverse proxy configuration (docker-compose.yml, traefik.yml, acme.json placeholder)
  - `apps/myapp/` - Example application showing proper Traefik label conventions
- **`servers/`** - Per-server deployment directories (created from templates)
- **`scripts/install/`** - Server provisioning scripts
  - `install.sh` - Main bootstrap script for fresh Debian 13 hosts
  - `install-debian.sh`, `install-btm.sh`, `install-codex.sh` - Specialized installers

## Common Commands

All commands use the Taskfile (requires `task` CLI):

```bash
# Start proxy and example app
task up

# Configure a new domain across templates
task set-domain DOMAIN=example.com

# Stop all services
task down
```

Manual docker-compose operations:
```bash
# Proxy management
docker compose -f proxy/docker-compose.yml up -d
docker compose -f proxy/docker-compose.yml down

# Application stack management
docker compose -f apps/<service>/docker-compose.yml up -d
docker compose -f apps/<service>/docker-compose.yml down

# Validate compose syntax
docker compose -f <path>/docker-compose.yml config -q
```

## Architecture

### Template-Based Multi-Server Pattern

1. **Templates** (`templates/server/`) contain base configurations with placeholder domain `enmeduranki.com`
2. **Server Deployment**: Copy `templates/server/` to `servers/<hostname>/`, then run `set-config-domain.sh <new-domain>` to customize
3. **Shared Network**: All services attach to external Docker network `proxy` (created by install.sh)
4. **Traefik Routing**: Services declare routing rules via Docker labels (see `apps/myapp/docker-compose.yml:6-19`)

### Traefik Configuration

- **Static config**: `proxy/traefik.yml` (v3.1) - entry points, ACME settings, provider configuration
- **Dynamic config**: Docker labels on service containers
- **TLS**: Automatic Let's Encrypt via HTTP challenge (resolver: `lehttp`)
- **Network isolation**: `exposedByDefault: false` - services must explicitly enable `traefik.enable=true`

### Service Label Pattern

From `templates/server/apps/myapp/docker-compose.yml`:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`subdomain.domain.com`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls.certresolver=lehttp"
  - "traefik.http.services.myapp-svc.loadbalancer.server.port=80"
  # HTTP->HTTPS redirect
  - "traefik.http.routers.myapp-http.entrypoints=web"
  - "traefik.http.routers.myapp-http.middlewares=myapp-https-redirect"
  - "traefik.http.middlewares.myapp-https-redirect.redirectscheme.scheme=https"
```

## Server Provisioning Workflow

1. Fresh Debian 13 host: Run `sudo bash scripts/install/install.sh`
   - Installs: Docker, UFW, git, dev tools (fzf, lazygit, lazydocker, chezmoi)
   - Configures firewall: SSH, HTTP (80), HTTPS (443)
   - Creates `/srv/proxy` and `/srv/apps` directories
   - Creates shared `proxy` Docker network
2. Copy `templates/server/` to `/srv/<hostname>/`
3. Update domain: `bash set-config-domain.sh <domain>` (recursively replaces `enmeduranki.com`)
4. Deploy: `cd /srv/<hostname> && task up`

## YAML & Shell Conventions

- YAML: 2-space indentation, alphabetical key ordering for labels/env/volumes
- Service names: lowercase (`whoami`, `traefik`)
- Container names: hyphenated (`myapp-whoami`)
- Shell scripts: `set -euo pipefail`, `[INFO]/[ERROR]` logging prefixes
- Validate with `shellcheck` before committing

## Configuration Scripts

- **`set-config-domain.sh <domain>`** - Search-replace `enmeduranki.com` → `<domain>` in all files under current directory
- **`update-codex.sh [stable|nightly]`** - Install/update OpenAI Codex CLI (supports Debian, user-local install to `~/.local/bin`)
