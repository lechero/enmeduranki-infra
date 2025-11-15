# Server Deployment Instructions for kingkontext.nl

**Date:** 2025-11-15
**Target Server:** enmeduranki
**Deployment Location:** `/home/enki/curriculum-vitae`
**Infrastructure Config:** `/srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl`
**APP_CODE_PATH (.env):** `/home/enki/curriculum-vitae`

---

## Overview

This document contains step-by-step instructions for deploying the curriculum-vitae application stack to the enmeduranki server. The deployment includes:

- **Web App** (Next.js 15) - `https://cv.kingkontext.nl`
- **CMS** (Strapi v5) - `https://cms.kingkontext.nl`
- **CV Generator Worker** - Background job processor
- **PostgreSQL 16** - Database
- **Apache Tika** - Document text extraction

All services are orchestrated via Docker Compose with Traefik handling SSL termination and routing.

---

## Prerequisites

### 1. Server Access

```bash
# SSH into the enmeduranki server
ssh enki@enmeduranki.com
# or
ssh enki@<server-ip>
```

### 2. Verify Infrastructure Setup

```bash
# Verify symlink structure
ls -la /srv
# Should show: /srv -> /home/enki/enmeduranki-infra/servers/enmeduranki

# Verify Traefik is running
cd /srv/proxy
docker compose ps
# Should show traefik container running

# Verify proxy network exists
docker network ls | grep proxy
# Should show: proxy (external)
```

### 3. DNS Configuration

Ensure these DNS A records point to your server IP:

- `cv.kingkontext.nl` → server IP
- `cms.kingkontext.nl` → server IP

Verify:
```bash
dig cv.kingkontext.nl +short
dig cms.kingkontext.nl +short
```

Both should return your server's public IP address.

---

## Deployment Steps

### Step 1: Clone Application Repository

```bash
# Create apps directory if it doesn't exist
mkdir -p /home/enki

# Clone the curriculum-vitae repository
cd /home/enki
git clone <repository-url> curriculum-vitae

# Verify the clone
ls -la curriculum-vitae
# Should show: apps/, packages/, markdown/, docker-compose.yml, etc.
```

### Step 2: Generate Secrets

```bash
# Navigate to CMS directory
cd /home/enki/curriculum-vitae/apps/cms

# Make the script executable
chmod +x generate-secrets.sh

# Generate all secrets and save to temporary file
./generate-secrets.sh > /tmp/kingkontext-secrets.txt

# View the generated secrets
cat /tmp/kingkontext-secrets.txt
```

**IMPORTANT:** Copy these secrets to a secure location (1Password, password manager, etc.). You'll need them in the next step.

### Step 3: Configure Environment Variables

```bash
# Navigate to deployment directory
cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl

# Copy example environment file
cp .env.example .env

# Edit the .env file
nano .env
```

Fill in all the values:

#### Required Secrets (from generate-secrets.sh)
1. `APP_KEYS` - 4 comma-separated base64 keys
2. `API_TOKEN_SALT` - Random base64 string
3. `ADMIN_JWT_SECRET` - Random base64 string
4. `TRANSFER_TOKEN_SALT` - Random base64 string
5. `JWT_SECRET` - Random base64 string
6. `STRAPI_ADMIN_CLIENT_PREVIEW_SECRET` - Random base64 string
7. `BETTER_AUTH_SECRET` - Random base64 string

#### Database Configuration
8. `POSTGRES_PASSWORD` - Create a strong password (32+ characters)
   ```bash
   # Generate with: node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
   ```

#### External API Keys
9. `OPENAI_API_KEY` - Your OpenAI API key (for CV generation)

#### Strapi API Token
10. `STRAPI_API_TOKEN` - **Leave blank for now**, we'll create this after Strapi starts

#### Optional Webhook
11. `N8N_OFFER_WEBHOOK_URL` - Leave blank if not using n8n automation

Save and close the file (Ctrl+X, then Y, then Enter).

**IMPORTANT:** The `.env` file contains sensitive secrets. Never commit it to git.

### Step 4: Build Docker Images

```bash
# Still in /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl
docker compose build

# This will take 5-10 minutes on first run
# You should see builds for: cms, cv-gen, web
```

Expected output:
```
[+] Building 300.0s (45/45) FINISHED
 => [cms internal] load build definition from Dockerfile
 => [cv-gen internal] load build definition from Dockerfile
 => [web internal] load build definition from Dockerfile
 ...
```

### Step 5: Start All Services

```bash
# Start all services in detached mode
docker compose up -d

# Watch logs to monitor startup
docker compose logs -f
```

Wait for all services to become healthy (~2 minutes). You should see:
- `postgres` - Database ready
- `cms` - Strapi started on port 1337
- `tika` - Tika server ready
- `cv-gen` - Worker polling Strapi
- `web` - Next.js app ready on port 3000

Press Ctrl+C to stop following logs (services continue running).

### Step 6: Verify Service Health

```bash
# Check service status
docker compose ps

# All services should show "(healthy)" or "running"
# Example output:
# NAME                  STATUS
# kingkontext-postgres  Up 2 minutes (healthy)
# kingkontext-cms       Up 2 minutes (healthy)
# kingkontext-cv-gen    Up 2 minutes
# kingkontext-tika      Up 2 minutes
# kingkontext-web       Up 2 minutes (healthy)
```

### Step 7: Create Strapi Admin Account

1. **Access Strapi admin panel:**
   ```bash
   # Open in browser:
   https://cms.kingkontext.nl/admin
   ```

2. **Create admin account** (first-time setup form):
   - First name: Your first name
   - Last name: Your last name
   - Email: Your admin email
   - Password: Strong password (save in password manager)

3. **Complete setup** and log in to Strapi admin panel

### Step 8: Generate Strapi API Token

1. **Navigate to API Tokens:**
   - In Strapi admin, click **Settings** (bottom left gear icon)
   - Under "Global settings", click **API Tokens**

2. **Create new token:**
   - Click **"Create new API Token"** button
   - **Name:** `Next.js Web App`
   - **Description:** `API token for cv.kingkontext.nl frontend`
   - **Token type:** `Full access`
   - **Duration:** `Unlimited`
   - Click **Save**

3. **Copy the token:**
   - The token is shown **only once** - copy it immediately
   - Save it in your password manager

### Step 9: Update Environment with API Token

```bash
# Edit .env file
cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl
nano .env

# Find the line:
# STRAPI_API_TOKEN=CHANGE_ME_CREATE_IN_STRAPI_ADMIN

# Replace with:
# STRAPI_API_TOKEN=<paste-your-token-here>

# Save and close (Ctrl+X, Y, Enter)
```

### Step 10: Restart Web Service

```bash
# Restart the web service to pick up the new token
docker compose restart web

# Watch logs to verify restart
docker compose logs -f web

# You should see:
# - Next.js starting
# - Server listening on port 3000
# - No authentication errors
```

### Step 11: Configure Strapi Permissions

1. **Navigate to Roles:**
   - In Strapi admin, click **Settings**
   - Under "Users & Permissions plugin", click **Roles**
   - Click **Public** role

2. **Enable offer permissions:**
   - Expand **Offer** section
   - Enable these permissions:
     - ✅ `find` - List all offers
     - ✅ `findOne` - Get single offer
   - Scroll to bottom and click **Save**

3. **Authenticated role** (default permissions are fine):
   - Authenticated users can manage their own offers via custom controller logic
   - No additional configuration needed

### Step 12: Create First User Account

1. **Access web app:**
   ```bash
   # Open in browser:
   https://cv.kingkontext.nl
   ```

2. **Create account:**
   - Click **Sign Up** or navigate to `/sign-in`
   - Fill in registration form:
     - Email: Your email
     - Password: Strong password
     - Name: Your name (optional)
   - Click **Sign Up**

3. **Verify authentication:**
   - You should be redirected to the home page
   - Account is created in Strapi's users collection

4. **Access offers page:**
   - Navigate to `/offers`
   - You should see the "Your offers" page
   - Initially empty (no offers yet)

---

## Verification Checklist

Run through this checklist to ensure everything is working:

- [ ] **Web app accessible:** `https://cv.kingkontext.nl` loads without SSL errors
- [ ] **CMS admin accessible:** `https://cms.kingkontext.nl/admin` loads
- [ ] **SSL certificates issued:** Both domains show valid Let's Encrypt certificates
- [ ] **User authentication works:** Can sign up and sign in
- [ ] **Offers page loads:** `/offers` page accessible when logged in
- [ ] **Upload form visible:** Can see "Upload Job Offer" form
- [ ] **All services healthy:** `docker compose ps` shows all healthy
- [ ] **No errors in logs:** `docker compose logs` shows no critical errors

### Test CV Generation Workflow

1. **Upload a test job offer:**
   - On `/offers` page, use "Upload Job Offer" form
   - Upload a PDF or paste job description text
   - Submit the form

2. **Verify offer appears:**
   - Offer should appear in "Recent offers" list below
   - Status: "uploaded" (yellow badge)

3. **Monitor cv-gen worker:**
   ```bash
   docker compose logs -f cv-gen
   ```
   - Worker should detect the new offer within 15 seconds
   - Status changes: uploaded → processing → preprocessed → cv_generated
   - Generated CV content should be stored

4. **View generated CV:**
   - Click on the offer in the list
   - Navigate to offer detail page
   - Generated CV should be visible
   - Status: "cv_generated" (green badge)

---

## Common Commands

### Service Management

```bash
# Navigate to deployment directory
cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl

# View all logs
docker compose logs -f

# View specific service logs
docker compose logs -f web
docker compose logs -f cms
docker compose logs -f cv-gen

# Restart a service
docker compose restart web

# Restart all services
docker compose restart

# Stop all services
docker compose down

# Stop and remove volumes (DANGER: deletes database!)
docker compose down -v
```

### Database Operations

```bash
# Access PostgreSQL shell
docker compose exec postgres psql -U strapi strapi

# Create database backup
docker compose exec postgres pg_dump -U strapi strapi > backup-$(date +%Y%m%d-%H%M%S).sql

# Compress backup
gzip backup-$(date +%Y%m%d-%H%M%S).sql

# Restore database from backup
gunzip -c backup.sql.gz | docker compose exec -T postgres psql -U strapi strapi

# Check database connection
docker compose exec postgres pg_isready -U strapi
```

### Resource Monitoring

```bash
# View container resource usage (CPU, RAM, Network)
docker stats

# Check disk usage
docker system df -v

# Check volume sizes
docker volume ls

# Cleanup unused resources (images, containers, volumes)
docker system prune -a
# WARNING: This removes ALL unused Docker resources
```

### Code Updates

```bash
# Pull latest code changes
cd /home/enki/curriculum-vitae
git pull

# Rebuild affected services
cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl
docker compose build

# Restart with new images
docker compose up -d

# Watch logs
docker compose logs -f
```

---

## Troubleshooting

### Web App Returns 502 Bad Gateway

**Symptoms:** Browser shows "502 Bad Gateway" when accessing `cv.kingkontext.nl`

**Diagnosis:**
```bash
# Check if web container is running
docker compose ps web

# Check web logs
docker compose logs web
```

**Common causes:**
- Build failed (check logs for TypeScript or build errors)
- `STRAPI_API_TOKEN` not set in `.env`
- CMS not accessible from internal network
- Next.js failed to start (port already in use)

**Solutions:**
```bash
# Verify environment variables
docker compose exec web env | grep STRAPI

# Restart web service
docker compose restart web

# Rebuild if needed
docker compose build web
docker compose up -d web
```

### CMS Admin Panel Won't Load

**Symptoms:** `cms.kingkontext.nl/admin` shows error or loading spinner indefinitely

**Diagnosis:**
```bash
# Check CMS logs
docker compose logs cms

# Check database connection
docker compose exec cms nc -zv postgres 5432
```

**Common causes:**
- Database connection failed (wrong password, postgres not ready)
- Missing environment variables (APP_KEYS, secrets)
- Build error during Strapi admin panel compilation
- Database migrations failed

**Solutions:**
```bash
# Verify database is healthy
docker compose exec postgres pg_isready -U strapi

# Restart CMS
docker compose restart cms

# Check environment variables
docker compose exec cms env | grep DATABASE

# Rebuild if needed
docker compose build cms
docker compose up -d cms
```

### CV Generator Not Processing Offers

**Symptoms:** Offers remain in "uploaded" state, cv-gen worker not picking them up

**Diagnosis:**
```bash
# Check worker logs
docker compose logs cv-gen

# Look for error messages about:
# - OPENAI_API_KEY invalid
# - STRAPI_API_TOKEN invalid
# - Cannot connect to Strapi
# - Tika service unavailable
```

**Common causes:**
- `OPENAI_API_KEY` not set or invalid
- `STRAPI_API_TOKEN` not set or invalid
- Tika service not running
- No offers in "uploaded" state
- Worker crashed (check logs for stack traces)

**Solutions:**
```bash
# Verify OpenAI API key
docker compose exec cv-gen env | grep OPENAI

# Verify Strapi connection
docker compose exec cv-gen curl http://cms:1337/_health

# Verify Tika connection
docker compose exec cv-gen curl http://tika:9998/tika

# Restart worker
docker compose restart cv-gen

# Check for offers in uploaded state
# (via Strapi admin or database query)
```

### SSL Certificate Not Issued

**Symptoms:** Browser shows "Not Secure" or certificate error

**Diagnosis:**
```bash
# Check Traefik logs
cd /srv/proxy
docker compose logs traefik | grep -i acme

# Verify DNS resolves correctly
dig cv.kingkontext.nl +short
dig cms.kingkontext.nl +short
```

**Common causes:**
- DNS not propagated yet (wait 5-10 minutes)
- Port 80 blocked (Let's Encrypt HTTP challenge fails)
- Rate limit reached (5 certificates per domain per week)
- Traefik not running or misconfigured

**Solutions:**
```bash
# Verify Traefik is running
cd /srv/proxy
docker compose ps

# Verify port 80 is accessible
curl -I http://cv.kingkontext.nl

# Check firewall rules
sudo ufw status

# Restart Traefik
docker compose restart traefik

# Wait 2-3 minutes for certificate issuance
```

### Database Connection Errors

**Symptoms:** CMS or cv-gen logs show "Connection refused" or "Authentication failed"

**Diagnosis:**
```bash
# Check if postgres is running
docker compose ps postgres

# Check postgres logs
docker compose logs postgres

# Test connection from CMS
docker compose exec cms nc -zv postgres 5432
```

**Common causes:**
- PostgreSQL not fully started (wait for health check)
- Wrong password in `.env`
- Database doesn't exist (bootstrap failed)
- Network connectivity issues

**Solutions:**
```bash
# Verify postgres health
docker compose exec postgres pg_isready -U strapi

# Check database exists
docker compose exec postgres psql -U strapi -l

# Verify credentials match
cat .env | grep POSTGRES

# Restart postgres
docker compose restart postgres
```

### Out of Disk Space

**Symptoms:** Services fail to start, build errors, "no space left on device"

**Diagnosis:**
```bash
# Check disk usage
df -h

# Check Docker disk usage
docker system df

# Check volume sizes
docker system df -v
```

**Solutions:**
```bash
# Remove unused images
docker image prune -a

# Remove unused volumes (WARNING: may delete data)
docker volume prune

# Remove build cache
docker builder prune -a

# Complete cleanup (DANGER: removes everything unused)
docker system prune -a --volumes

# Monitor space
watch -n 5 df -h
```

---

## Security Checklist

After deployment, verify these security measures:

- [ ] **All secrets are strong:** Generated with cryptographically secure randomness (32+ bytes)
- [ ] **PostgreSQL password is strong:** 32+ characters, not in any dictionary
- [ ] **Database not exposed:** Only accessible via internal Docker network
- [ ] **STRAPI_API_TOKEN has minimal permissions:** Full access token stored securely
- [ ] **OpenAI API key has usage limits:** Set spending limits in OpenAI dashboard
- [ ] **Firewall configured:** Only ports 22 (SSH), 80 (HTTP), 443 (HTTPS) open
- [ ] **Backups configured:** Database backups scheduled (see next section)
- [ ] **Monitoring set up:** Uptime monitoring and log aggregation
- [ ] **SSL certificates valid:** Both domains show valid HTTPS certificates
- [ ] **Environment file secured:** `.env` file is not in git, has restricted permissions (600)

```bash
# Verify .env permissions
ls -la .env
# Should show: -rw------- (600) or -rw-r----- (640)

# Fix if needed
chmod 600 .env

# Verify firewall
sudo ufw status

# Should show:
# 22/tcp  ALLOW
# 80/tcp  ALLOW
# 443/tcp ALLOW
```

---

## Backup Configuration

### Manual Database Backup

```bash
cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl

# Create backup
docker compose exec postgres pg_dump -U strapi strapi > /tmp/kingkontext-backup-$(date +%Y%m%d-%H%M%S).sql

# Compress
gzip /tmp/kingkontext-backup-*.sql

# Copy to secure location
cp /tmp/kingkontext-backup-*.sql.gz /srv/backups/kingkontext/
```

### Automated Daily Backups

Create backup script:

```bash
# Create backup directory
sudo mkdir -p /srv/backups/kingkontext
sudo chown -R $USER:$USER /srv/backups

# Create backup script
sudo nano /srv/scripts/backup-kingkontext.sh
```

Paste this content:

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/srv/backups/kingkontext"
DATE=$(date +%Y%m%d-%H%M%S)
COMPOSE_DIR="/srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl"

mkdir -p "$BACKUP_DIR"

cd "$COMPOSE_DIR"

# Backup database
docker compose exec -T postgres pg_dump -U strapi strapi > "$BACKUP_DIR/db-$DATE.sql"

# Compress
gzip "$BACKUP_DIR/db-$DATE.sql"

# Keep only last 30 days
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +30 -delete

echo "[$(date)] Backup completed: $BACKUP_DIR/db-$DATE.sql.gz"
```

Make executable:

```bash
sudo chmod +x /srv/scripts/backup-kingkontext.sh
```

Schedule with cron:

```bash
# Edit crontab
crontab -e

# Add this line (runs daily at 2 AM)
0 2 * * * /srv/scripts/backup-kingkontext.sh >> /var/log/kingkontext-backup.log 2>&1
```

Test the backup:

```bash
# Run manually
/srv/scripts/backup-kingkontext.sh

# Verify backup created
ls -lh /srv/backups/kingkontext/

# Check log
tail /var/log/kingkontext-backup.log
```

---

## Monitoring Setup

### Health Check Endpoints

All services expose health check endpoints:

- **Web:** `https://cv.kingkontext.nl/api/health`
- **CMS:** `https://cms.kingkontext.nl/_health`

Test them:

```bash
curl https://cv.kingkontext.nl/api/health
# Should return: {"status":"ok","timestamp":"...","uptime":...}

curl https://cms.kingkontext.nl/_health
# Should return: {"status":"ok"}
```

### Uptime Monitoring

Recommended: **UptimeRobot** (free tier)

1. Sign up at https://uptimerobot.com
2. Add monitors:
   - **CV App:** `https://cv.kingkontext.nl/api/health` (every 5 min)
   - **CMS:** `https://cms.kingkontext.nl/_health` (every 5 min)
3. Configure alerts (email, Slack, etc.)

### Log Aggregation

#### Local Log Access

```bash
# View all logs
docker compose logs -f

# Follow specific service
docker compose logs -f web

# Last 100 lines
docker compose logs --tail=100 cms

# Search logs
docker compose logs | grep -i error
```

#### External Log Aggregation (Optional)

Recommended services:
- **Papertrail** (free tier: 50 MB/month)
- **CloudWatch Logs** (AWS)
- **Datadog** (paid)

### Resource Monitoring

```bash
# Real-time container stats
docker stats

# Disk usage
df -h
docker system df

# Memory usage
free -h

# CPU usage
top
# or
htop
```

---

## Performance Optimization

### Database Connection Pooling

Edit database config:

```bash
cd /home/enki/curriculum-vitae/apps/cms
nano config/database.ts
```

Update pool settings:

```typescript
pool: {
  min: 2,
  max: 10,
  acquireTimeoutMillis: 60000,
  idleTimeoutMillis: 600000,
}
```

Rebuild CMS:

```bash
cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl
docker compose build cms
docker compose up -d cms
```

### Resource Limits

Add resource limits to docker-compose.yml:

```yaml
services:
  web:
    # ... existing config
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 512M
```

Apply changes:

```bash
docker compose up -d
```

### Next.js Caching

The web service already uses a persistent volume for `.next/cache`. This improves build times significantly.

Verify:

```bash
docker compose exec web ls -la /app/.next/cache
```

---

## Disaster Recovery

### Full System Restore

If you need to completely restore the system:

1. **Provision new server:**
   ```bash
   # Run install script on fresh Debian 13
   sudo bash scripts/install/install.sh
   ```

2. **Clone repositories:**
   ```bash
   cd /home/enki
   git clone <repository-url> curriculum-vitae
   ```

3. **Restore .env file:**
   ```bash
   cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl
   # Copy .env from backup (1Password, etc.)
   nano .env
   # Paste contents and save
   chmod 600 .env
   ```

4. **Start services:**
   ```bash
   docker compose up -d
   ```

5. **Restore database:**
   ```bash
   # Wait for postgres to be healthy
   docker compose ps postgres

   # Restore from backup
   gunzip -c /srv/backups/kingkontext/db-YYYYMMDD-HHMMSS.sql.gz | \
     docker compose exec -T postgres psql -U strapi strapi
   ```

6. **Verify:**
   - Access `https://cv.kingkontext.nl`
   - Log in with existing account
   - Verify offers are visible
   - Test CV generation

### Rollback to Previous Version

If deployment fails:

```bash
# Stop services
docker compose down

# Pull previous version
cd /home/enki/curriculum-vitae
git log --oneline -10
git checkout <previous-commit-hash>

# Rebuild
cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl
docker compose build
docker compose up -d
```

---

## Cost Estimation

### Monthly Costs

| Item | Cost Range |
|------|------------|
| **VPS** (2-4GB RAM, 2-4 vCPU) | $10-20 |
| **Domain registration** (annual/12) | $1 |
| **OpenAI API** (CV generation) | $5-50 |
| **Backups** (local storage) | $0 |
| **Backups** (optional S3/CloudFlare R2) | $0-5 |
| **Monitoring** (UptimeRobot free tier) | $0 |
| **Total** | **$16-76/month** |

### Resource Requirements

**Minimum:**
- 2GB RAM
- 2 vCPU
- 40GB storage
- 2TB bandwidth

**Recommended:**
- 4GB RAM (better performance, room for growth)
- 2-4 vCPU
- 80GB storage
- Unlimited bandwidth

**Recommended VPS providers:**
- **Hetzner Cloud CX21:** ~$7/month (2GB RAM, 2 vCPU, 40GB, 20TB bandwidth)
- **DigitalOcean Droplet:** ~$12/month (2GB RAM, 1 vCPU, 50GB, 2TB bandwidth)
- **Linode Shared:** ~$12/month (2GB RAM, 1 vCPU, 50GB, 2TB bandwidth)

---

## Support & Documentation

### Repository Documentation

- **Main README:** `/home/enki/curriculum-vitae/README.md`
- **CLAUDE.md:** `/home/enki/curriculum-vitae/CLAUDE.md` (project architecture)
- **Deployment README:** `/srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl/README.md`
- **Production setup doc:** `/home/enki/curriculum-vitae/state/production-deployment-setup.md`

### External Documentation

- **Next.js:** https://nextjs.org/docs
- **Strapi v5:** https://docs.strapi.io
- **Docker Compose:** https://docs.docker.com/compose/
- **Traefik v3:** https://doc.traefik.io/traefik/
- **BetterAuth:** https://www.better-auth.com/docs

### Useful Commands Reference

```bash
# Quick reference card
cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl

# Status check
docker compose ps

# View all logs
docker compose logs -f

# Restart everything
docker compose restart

# Rebuild and restart
docker compose build && docker compose up -d

# Database backup
docker compose exec postgres pg_dump -U strapi strapi > backup.sql

# Pull code updates
cd /home/enki/curriculum-vitae && git pull

# Apply updates
cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl
docker compose build && docker compose up -d
```

---

## Post-Deployment Tasks

After successful deployment, complete these tasks:

### 1. Test Full Workflow

- [ ] Create user account at `https://cv.kingkontext.nl/sign-in`
- [ ] Upload a test job offer (PDF or text)
- [ ] Verify offer appears in "Recent offers" list
- [ ] Monitor cv-gen worker logs: `docker compose logs -f cv-gen`
- [ ] Wait for CV generation (15-30 seconds)
- [ ] Verify CV appears in offer detail page
- [ ] Download generated CV

### 2. Configure Automated Backups

- [ ] Create `/srv/scripts/backup-kingkontext.sh` script
- [ ] Make script executable
- [ ] Add cron job for daily 2 AM backups
- [ ] Test backup script manually
- [ ] Verify backup file created in `/srv/backups/kingkontext/`

### 3. Set Up Monitoring

- [ ] Create UptimeRobot account (or similar)
- [ ] Add monitor for `https://cv.kingkontext.nl/api/health`
- [ ] Add monitor for `https://cms.kingkontext.nl/_health`
- [ ] Configure email/Slack alerts
- [ ] Test alerts (pause monitor, verify notification)

### 4. Performance Baseline

- [ ] Document initial response times
  ```bash
  curl -w "@curl-format.txt" -o /dev/null -s https://cv.kingkontext.nl
  ```
- [ ] Record container resource usage: `docker stats`
- [ ] Document disk usage: `df -h && docker system df`
- [ ] Set up resource usage tracking (optional)

### 5. Security Hardening

- [ ] Verify firewall rules: `sudo ufw status`
- [ ] Verify .env permissions: `ls -la .env` (should be 600)
- [ ] Verify database not exposed: `sudo netstat -tlnp | grep 5432`
- [ ] Set OpenAI API spending limits
- [ ] Enable 2FA on server SSH (optional)
- [ ] Set up fail2ban (optional)

### 6. Documentation

- [ ] Document any custom configuration changes
- [ ] Update team runbooks with server details
- [ ] Share .env backup location with team
- [ ] Document admin credentials storage (1Password, etc.)

---

## Success Criteria

Deployment is successful when:

✅ All services show "(healthy)" in `docker compose ps`
✅ Web app accessible via `https://cv.kingkontext.nl` with valid SSL
✅ CMS admin accessible via `https://cms.kingkontext.nl/admin` with valid SSL
✅ User can sign up and sign in
✅ User can upload job offer
✅ CV generator processes offer within 30 seconds
✅ Generated CV appears in UI
✅ No critical errors in logs
✅ SSL certificates automatically issued by Let's Encrypt
✅ Automated backups configured and tested
✅ Uptime monitoring configured

---

## Rollback Plan

If deployment fails at any step:

1. **Stop all services:**
   ```bash
   docker compose down
   ```

2. **Check logs for errors:**
   ```bash
   docker compose logs > /tmp/deployment-error.log
   cat /tmp/deployment-error.log | grep -i error
   ```

3. **Identify issue:**
   - Build failure → Check Dockerfile, dependency versions
   - Runtime error → Check .env configuration
   - Network error → Check Traefik, DNS, firewall
   - Database error → Check postgres logs, credentials

4. **Fix issue** and retry:
   ```bash
   docker compose build
   docker compose up -d
   docker compose logs -f
   ```

5. **If unfixable, revert code:**
   ```bash
   cd /home/enki/curriculum-vitae
   git checkout <previous-working-commit>
   cd /srv/enmeduranki-infra/servers/enmeduranki/apps/kingkontext.nl
   docker compose build
   docker compose up -d
   ```

---

## Changelog

**2025-11-15** - Initial production deployment guide
- Next.js 15 web app (`cv.kingkontext.nl`)
- Strapi v5 CMS (`cms.kingkontext.nl`)
- CV generator worker with OpenAI integration
- PostgreSQL 16 database
- Apache Tika document extraction
- Traefik SSL termination with Let's Encrypt
- User-owned offers with authentication
- BetterAuth credentials authentication
- Automated health checks
- Docker Compose orchestration

---

**End of deployment instructions. Good luck! 🚀**
