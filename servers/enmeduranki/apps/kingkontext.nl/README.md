# kingkontext.nl Production Deployment

Complete CV management system with Next.js frontend, Strapi CMS, CV generator worker, and PostgreSQL database.

---

## Architecture

```
Internet
   ↓
Traefik (proxy network)
   ├── cv.kingkontext.nl → Next.js Web App (port 3000)
   └── cms.kingkontext.nl → Strapi CMS (port 1337)
       ↓
PostgreSQL (internal network)
       ↑
Workers (internal network):
  ├── CV Generator Worker (polls Strapi, generates CVs)
  ├── Offer Processor Worker (enriches offers)
  ├── PDF Export Worker (generates PDFs)
  ├── Offer Finder Worker (crawls external providers)
  └── Possibilities Discovery Worker (generates search ideas)
       ↑
Apache Tika (document text extraction)
```

**Services:**
- **web** - Next.js 15 app with interactive CV timeline and offer management
- **cms** - Strapi v5 headless CMS for content management
- **cv-gen** - TypeScript worker that generates tailored CVs using LLM
- **offer-processor** - Worker that enriches job offers and processes them
- **pdf-export** - Worker that generates PDF versions of CVs
- **offer-finder** - Daemon that crawls external providers for job offers
- **possibilities-discovery** - Worker that generates search ideas from assignments
- **postgres** - PostgreSQL 16 database
- **tika** - Apache Tika for document text extraction

**Networks:**
- `proxy` (external) - Traefik reverse proxy network with SSL
- `kingkontext-nl-internal` (bridge) - Internal service communication

---

## Prerequisites

1. **Server Access**: SSH to `enmeduranki` server
2. **Repository**: Clone curriculum-vitae to `/home/enki/curriculum-vitae` (default `APP_CODE_PATH`; adjust `.env` if you keep it elsewhere)
3. **Traefik**: Proxy must be running on external `proxy` network
4. **DNS**: Point `kingkontext.nl` and `cms.kingkontext.nl` to server IP

Set `APP_CODE_PATH` in `.env` (default `/home/enki/curriculum-vitae`) to the location of the cloned repository before running the commands below.

---

## Quick Start

### 1. Clone Repository

```bash
# On the server
mkdir -p /home/enki
cd /home/enki
git clone <repository-url> curriculum-vitae
```

### 2. Generate Secrets

```bash
cd /home/enki/curriculum-vitae/apps/cms
./generate-secrets.sh > /tmp/secrets.txt
cat /tmp/secrets.txt
```

**Copy all the output** - you'll need it for the next step.

### 3. Configure Environment

```bash
cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl
cp .env.example .env
nano .env
```

Fill in all the values:
1. **Paste secrets** from step 2
2. **Set PostgreSQL password** (strong, random)
3. **Add OpenAI API key** (for CV generation)
4. **STRAPI_API_TOKEN** - Leave blank, we'll create this after Strapi starts

### 4. Build & Deploy

```bash
# Build images (first time or after code changes)
docker compose build

# Start all services
docker compose up -d

# Watch logs
docker compose logs -f
```

Wait for all services to become healthy (~2 minutes).

### 5. Create Strapi Admin & API Token

1. **Access Strapi admin**: https://cms.kingkontext.nl/admin
2. **Create admin account** (first-time setup)
3. **Generate API token**:
   - Go to Settings → API Tokens
   - Click "Create new API Token"
   - Name: "Next.js Web App"
   - Token type: "Full access"
   - Duration: "Unlimited"
   - Copy the token
4. **Update .env**:
   ```bash
   nano .env
   # Set STRAPI_API_TOKEN=<paste-token-here>
   ```
5. **Restart web service**:
   ```bash
   docker compose restart web
   ```

### 6. Configure Strapi Permissions

1. Go to **Settings → Roles → Public**
2. Enable permissions:
   - **Offer**: `find`, `findOne`
   - **Users-Permissions**: (no changes needed)
3. Save

### 7. Create First User

1. Access: https://cv.kingkontext.nl/sign-in
2. Create account (uses Strapi authentication)
3. Verify you can access /offers page

---

## Verification Checklist

- [ ] Web app accessible at https://cv.kingkontext.nl
- [ ] CMS admin accessible at https://cms.kingkontext.nl/admin
- [ ] SSL certificates automatically issued by Traefik/Let's Encrypt
- [ ] Can sign in to web app
- [ ] Can access /offers page
- [ ] Can upload a test job offer
- [ ] CV generator processes offer (check logs: `docker compose logs cv-gen`)
- [ ] Generated CV appears in offer detail page

---

## Common Commands

```bash
# View logs (all services)
docker compose logs -f

# View specific service logs
docker compose logs -f web
docker compose logs -f cms
docker compose logs -f cv-gen
docker compose logs -f offer-processor
docker compose logs -f pdf-export
docker compose logs -f offer-finder
docker compose logs -f possibilities-discovery

# Restart a service
docker compose restart web

# Rebuild after code changes
docker compose build web
docker compose up -d web

# Database backup
docker compose exec postgres pg_dump -U strapi strapi > backup-$(date +%Y%m%d-%H%M%S).sql

# Restore database
docker compose exec -T postgres psql -U strapi strapi < backup.sql

# Access database shell
docker compose exec postgres psql -U strapi strapi

# Stop all services
docker compose down

# Remove volumes (DANGER: deletes database and uploads)
docker compose down -v
```

---

## Updating Code

```bash
# On the server
cd /home/enki/curriculum-vitae
git pull

# Rebuild and restart affected services
cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl
docker compose build
docker compose up -d
```

---

## Monitoring

### Health Checks

All services have health checks:
```bash
docker compose ps
```

Look for `(healthy)` status.

### Resource Usage

```bash
docker stats
```

### Disk Usage

```bash
# Check volume sizes
docker system df -v

# Cleanup unused resources
docker system prune -a
```

---

## Troubleshooting

### Web app returns 502

**Check if web container is running:**
```bash
docker compose ps web
docker compose logs web
```

**Common causes:**
- Build failed (check logs for errors)
- STRAPI_API_TOKEN not set
- CMS not accessible from internal network

### CMS admin panel won't load

**Check Strapi logs:**
```bash
docker compose logs cms
```

**Common causes:**
- Database connection failed
- Missing environment variables
- Build error during admin panel compilation

### CV generator not processing offers

**Check worker logs:**
```bash
docker compose logs cv-gen
```

**Common causes:**
- OPENAI_API_KEY not set or invalid
- STRAPI_API_TOKEN not set or invalid
- Tika service not running
- No offers in "uploaded" state

### Database connection errors

**Verify PostgreSQL is healthy:**
```bash
docker compose exec postgres pg_isready -U strapi
```

**Check connection from CMS:**
```bash
docker compose exec cms nc -zv postgres 5432
```

### SSL certificate errors

**Check Traefik logs:**
```bash
cd /srv/enmeduranki-infra/servers/enmeduranki/proxy
docker compose logs traefik
```

**Verify DNS:**
```bash
dig kingkontext.nl
dig cms.kingkontext.nl
```

Both should point to your server IP.

---

## Security Checklist

- [ ] All secrets generated with strong randomness
- [ ] PostgreSQL password is strong (32+ characters)
- [ ] Database not exposed externally (only internal network)
- [ ] STRAPI_API_TOKEN has minimal required permissions
- [ ] OpenAI API key has usage limits configured
- [ ] Firewall allows only ports 80, 443, and SSH
- [ ] Backups configured and tested
- [ ] Monitoring/alerting set up

---

## Performance Optimization

### Database Connection Pooling

Edit `/home/enki/curriculum-vitae/apps/cms/config/database.ts`:

```typescript
pool: {
  min: 2,
  max: 10,
  acquireTimeoutMillis: 60000,
  idleTimeoutMillis: 600000,
}
```

Rebuild CMS after changes.

### Next.js Caching

The web container uses a persistent volume for `.next/cache` to improve build times.

### Resource Limits

Add to docker-compose.yml under each service:

```yaml
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 1G
    reservations:
      cpus: '0.5'
      memory: 512M
```

---

## Backup Strategy

### Automated Daily Backups

Create `/srv/scripts/backup-kingkontext.sh`:

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/srv/backups/kingkontext"
DATE=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl

# Backup database
docker compose exec -T postgres pg_dump -U strapi strapi > "$BACKUP_DIR/db-$DATE.sql"

# Compress
gzip "$BACKUP_DIR/db-$DATE.sql"

# Keep only last 30 days
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +30 -delete

echo "[$(date)] Backup completed: $BACKUP_DIR/db-$DATE.sql.gz"
```

Add to crontab:
```bash
crontab -e
# Add: 0 2 * * * /srv/scripts/backup-kingkontext.sh >> /var/log/kingkontext-backup.log 2>&1
```

---

## Disaster Recovery

### Full System Restore

1. **Restore repository:**
   ```bash
   cd /srv
   git clone <repository-url> curriculum-vitae
   ```

2. **Restore .env:**
   ```bash
   cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl
   # Copy .env from backup
   ```

3. **Start services:**
   ```bash
   docker compose up -d
   ```

4. **Restore database:**
   ```bash
   gunzip -c backup.sql.gz | docker compose exec -T postgres psql -U strapi strapi
   ```

5. **Verify:**
   - Access https://cv.kingkontext.nl
   - Check /offers page
   - Verify data integrity

---

## Cost Estimation

**Monthly costs for this deployment:**

- **Server (VPS)**: ~$10-20/month (2GB RAM, 2 vCPU)
- **Domain**: ~$12/year (~$1/month)
- **OpenAI API**: ~$5-50/month (depends on CV generation volume)
- **Backups**: $0 (local) or ~$5/month (S3)

**Total: ~$16-76/month**

---

## Support & Documentation

- **CV Repository**: `/home/enki/curriculum-vitae`
- **Strapi Docs**: https://docs.strapi.io
- **Next.js Docs**: https://nextjs.org/docs
- **Traefik Docs**: https://doc.traefik.io/traefik/

---

## Changelog

**2025-11-15** - Initial production deployment
- Next.js 15 web app
- Strapi v5 CMS
- CV generator worker
- PostgreSQL 16
- Apache Tika
- Traefik SSL integration
