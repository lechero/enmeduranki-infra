#!/usr/bin/env bash
set -euo pipefail

# Get the repository root directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Prompt for server name
read -p "Enter server name: " SERVER_NAME

if [[ -z "$SERVER_NAME" ]]; then
  echo "[ERROR] Server name cannot be empty."
  exit 1
fi

# Validate server name (alphanumeric, hyphens, underscores only)
if [[ ! "$SERVER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "[ERROR] Server name must contain only alphanumeric characters, hyphens, and underscores."
  exit 1
fi

SERVER_DIR="$REPO_ROOT/servers/$SERVER_NAME"

# Check if server already exists
if [[ -d "$SERVER_DIR" ]]; then
  echo "[ERROR] Server '$SERVER_NAME' already exists at $SERVER_DIR"
  exit 1
fi

echo "[INFO] Creating server directory: $SERVER_DIR"
mkdir -p "$SERVER_DIR"

echo "[INFO] Copying proxy configuration from templates/server/proxy..."
cp -r "$REPO_ROOT/templates/server/proxy" "$SERVER_DIR/proxy"

echo "[INFO] Copying .env.default to server directory..."
cp "$REPO_ROOT/templates/server/.env.default" "$SERVER_DIR/.env"

echo "[INFO] Creating symlink from ~/srv to $SERVER_DIR..."
if [[ -e "$HOME/srv" || -L "$HOME/srv" ]]; then
  echo "[WARN] ~/srv already exists. Skipping symlink creation."
  echo "       To link manually, run: ln -sfn \"$SERVER_DIR\" \"$HOME/srv\""
else
  ln -s "$SERVER_DIR" "$HOME/srv"
  echo "[INFO] Symlink created: ~/srv -> $SERVER_DIR"
fi

echo "[INFO] Updating .env in repository root..."
echo "CURRENT_SERVER=$SERVER_NAME" > "$REPO_ROOT/.env"

echo ""
echo "✅ Server '$SERVER_NAME' set up successfully!"
echo ""
echo "Next steps:"
echo "  1. Edit servers/$SERVER_NAME/.env to configure:"
echo "     - ACME_EMAIL"
echo "     - APP_DOMAIN"
echo "     - TRAEFIK_LOG_LEVEL"
echo "  2. Navigate to the server directory: cd ~/srv"
echo "  3. Start services: docker compose -f proxy/docker-compose.yml up -d"
