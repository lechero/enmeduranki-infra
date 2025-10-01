#!/usr/bin/env bash
set -euo pipefail

# Get the repository root directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Check if .env exists and read CURRENT_SERVER
if [[ ! -f "$REPO_ROOT/.env" ]]; then
  echo "[ERROR] No .env file found. Run 'task server:add' first to set up a server."
  exit 1
fi

source "$REPO_ROOT/.env"

if [[ -z "${CURRENT_SERVER:-}" ]]; then
  echo "[ERROR] CURRENT_SERVER not set in .env. Run 'task server:add' first."
  exit 1
fi

SERVER_DIR="$REPO_ROOT/servers/$CURRENT_SERVER"

if [[ ! -d "$SERVER_DIR" ]]; then
  echo "[ERROR] Server directory not found: $SERVER_DIR"
  exit 1
fi

# Prompt for service name
read -p "Enter service name: " SERVICE_NAME

if [[ -z "$SERVICE_NAME" ]]; then
  echo "[ERROR] Service name cannot be empty."
  exit 1
fi

# Validate service name (alphanumeric, hyphens, underscores only)
if [[ ! "$SERVICE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "[ERROR] Service name must contain only alphanumeric characters, hyphens, and underscores."
  exit 1
fi

SERVICE_DIR="$SERVER_DIR/apps/$SERVICE_NAME"

# Check if service already exists
if [[ -d "$SERVICE_DIR" ]]; then
  echo "[ERROR] Service '$SERVICE_NAME' already exists at $SERVICE_DIR"
  exit 1
fi

# Prompt for domains (comma-separated)
read -p "Enter domain(s) (comma-separated): " DOMAINS_INPUT

if [[ -z "$DOMAINS_INPUT" ]]; then
  echo "[ERROR] At least one domain is required."
  exit 1
fi

# Prompt for image
read -p "Enter Docker image (default: traefik/whoami): " SERVICE_IMAGE
SERVICE_IMAGE="${SERVICE_IMAGE:-traefik/whoami}"

# Create service directory
echo "[INFO] Creating service directory: $SERVICE_DIR"
mkdir -p "$SERVICE_DIR"

# Create .env file
echo "[INFO] Creating .env file..."
cat > "$SERVICE_DIR/.env" <<EOF
SERVICE_NAME=$SERVICE_NAME
SERVICE_DOMAINS=$DOMAINS_INPUT
SERVICE_IMAGE=$SERVICE_IMAGE
EOF

# Parse domains into array
IFS=',' read -ra DOMAINS <<< "$DOMAINS_INPUT"
# Trim whitespace from each domain
for i in "${!DOMAINS[@]}"; do
  DOMAINS[$i]=$(echo "${DOMAINS[$i]}" | xargs)
done

# Generate Traefik Host rules
HOST_RULES=""
for domain in "${DOMAINS[@]}"; do
  if [[ -z "$HOST_RULES" ]]; then
    HOST_RULES="Host(\`${domain}\`)"
  else
    HOST_RULES="${HOST_RULES} || Host(\`${domain}\`)"
  fi
done

# Generate docker-compose.yml
echo "[INFO] Generating docker-compose.yml..."
cat > "$SERVICE_DIR/docker-compose.yml" <<EOF
services:
  ${SERVICE_NAME}:
    image: ${SERVICE_IMAGE}
    container_name: ${CURRENT_SERVER}-${SERVICE_NAME}
    env_file:
      - .env
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${SERVICE_NAME}.rule=${HOST_RULES}"
      - "traefik.http.routers.${SERVICE_NAME}.entrypoints=websecure"
      - "traefik.http.routers.${SERVICE_NAME}.service=${SERVICE_NAME}-svc"
      - "traefik.http.routers.${SERVICE_NAME}.tls=true"
      - "traefik.http.routers.${SERVICE_NAME}.tls.certresolver=lehttp"
      - "traefik.http.middlewares.${SERVICE_NAME}-headers.headers.stsSeconds=31536000"
      - "traefik.http.routers.${SERVICE_NAME}.middlewares=${SERVICE_NAME}-headers@docker"
      - "traefik.http.routers.${SERVICE_NAME}-http.service=${SERVICE_NAME}-svc"
      - "traefik.http.routers.${SERVICE_NAME}-http.rule=${HOST_RULES}"
      - "traefik.http.routers.${SERVICE_NAME}-http.entrypoints=web"
      - "traefik.http.routers.${SERVICE_NAME}-http.middlewares=${SERVICE_NAME}-https-redirect"
      - "traefik.http.middlewares.${SERVICE_NAME}-https-redirect.redirectscheme.scheme=https"
      - "traefik.http.services.${SERVICE_NAME}-svc.loadbalancer.server.port=80"
    networks:
      - proxy
    restart: unless-stopped

networks:
  proxy:
    external: true
EOF

echo ""
echo "✅ Service '$SERVICE_NAME' created successfully!"
echo ""
echo "Configuration:"
echo "  Service name: $SERVICE_NAME"
echo "  Domain(s): $DOMAINS_INPUT"
echo "  Image: $SERVICE_IMAGE"
echo "  Location: $SERVICE_DIR"
echo ""
echo "Next steps:"
echo "  1. Edit $SERVICE_DIR/.env to adjust configuration if needed"
echo "  2. Start the service:"
echo "     cd $SERVICE_DIR"
echo "     docker compose up -d"
echo "  3. Or start from ~/srv/apps/$SERVICE_NAME"
