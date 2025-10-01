#!/usr/bin/env bash
# Bootstrap Docker, Traefik prerequisites, and baseline security on Debian 13

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] install.sh must be run as root (use sudo)." >&2
  exit 1
fi

TARGET_USER="${SUDO_USER:-${USER}}"
if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
  TARGET_USER="root"
fi

echo "[INFO] Updating apt cache and upgrading packages..."
apt-get update -y
apt-get upgrade -y

echo "[INFO] Installing prerequisites (curl, ufw)..."
apt-get install -y curl ufw git fzf lazygit tree zoxide starship

git config --global user.name "Miguel Fuentes"
git config --global user.email "miguel@midgetgiraffe.com"
git config --global pull.rebase true

sh -c "$(curl -fsLS get.chezmoi.io)"
curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash

echo "[INFO] Installing Docker Engine via convenience script..."
curl -fsSL https://get.docker.com | sh

if [[ "${TARGET_USER}" != "root" ]]; then
  echo "[INFO] Adding ${TARGET_USER} to docker group (if not already)."
  usermod -aG docker "${TARGET_USER}" || true
else
  echo "[WARN] Running as root; skipping docker group modification."
fi

echo "[INFO] Configuring UFW rules..."
ufw allow OpenSSH || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true
ufw --force enable || true

echo "[INFO] Creating /srv directory structure..."
mkdir -p /srv/proxy /srv/apps

echo "[INFO] Creating shared Docker network 'proxy' (if missing)..."
if ! docker network inspect proxy >/dev/null 2>&1; then
  docker network create proxy
else
  echo "[INFO] Docker network 'proxy' already exists; skipping."
fi

echo "[INFO] Bootstrap complete. You may need to log out and back in for docker group changes to apply."
