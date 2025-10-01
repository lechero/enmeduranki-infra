#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# update-codex.sh (Debian-friendly, non-root user default)
# Install Codex CLI globally for the current user (nightly by default).
#
# Defaults:
# - Installs into $HOME/.local/bin (no sudo required)
# - Falls back to system dirs if explicitly requested via INSTALL_PATH/INSTALL_DIR
# - If a system dir isn't writable, will attempt sudo (AUTO_SUDO=1)
# - On Debian/Ubuntu, can auto-install deps (curl, jq, unzip, ca-certificates)
#
# Usage:
#   ./update-codex.sh            # nightly (default)
#   ./update-codex.sh stable
#
# Env overrides:
#   REPO="owner/name"                   # default: openai/codex
#   ASSET_NAME_HINT="codex"             # expected binary name inside archives
#   INSTALL_DIR="$HOME/.local/bin"      # directory to install into
#   INSTALL_PATH="/desired/path/codex"  # explicit full path (overrides INSTALL_DIR)
#   LINK_NAME="codex"                   # symlink/wrapper name to create in INSTALL_DIR
#   AUTO_SUDO=1                         # try sudo if INSTALL_DIR not writable
#   SKIP_APT=0                          # set to 1 to skip apt auto-install of deps
#   GITHUB_TOKEN="..."                  # optional, avoid GitHub API rate limits
# ==============================================================================

REPO="${REPO:-openai/codex}"
CHANNEL="${1:-nightly}"                 # nightly (default) | stable
ASSET_NAME_HINT="${ASSET_NAME_HINT:-codex}"
AUTO_SUDO="${AUTO_SUDO:-1}"
SKIP_APT="${SKIP_APT:-0}"
LINK_NAME="${LINK_NAME:-codex}"

# ---------- OS/ARCH ----------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"        # darwin | linux | ...
RAW_ARCH="$(uname -m | tr '[:upper:]' '[:lower:]')"  # x86_64|arm64|aarch64|...
case "$RAW_ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) ARCH="$RAW_ARCH" ;;
esac

IS_DEBIAN=0
if [[ "$OS" == "linux" && -f /etc/debian_version ]]; then
  IS_DEBIAN=1
fi

# ---------- Dependencies ----------
need_cmds=(curl tar)
opt_cmds=(jq unzip) # used for prerelease JSON parsing / .zip extraction

ensure_deps() {
  local missing=()
  for c in "${need_cmds[@]}"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  for c in "${opt_cmds[@]}"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done

  # TLS roots (best-effort)
  if [[ "$OS" == "linux" ]] && ! ls /etc/ssl/certs/* >/dev/null 2>&1; then
    missing+=("ca-certificates")
  fi

  if (( ${#missing[@]} > 0 )); then
    echo "→ Missing tools: ${missing[*]}"
    if (( IS_DEBIAN == 1 )) && (( SKIP_APT == 0 )); then
      if command -v sudo >/dev/null 2>&1; then
        echo "→ Installing with sudo apt-get: ${missing[*]}"
        sudo apt-get update -y
        pkgs=()
        for m in "${missing[@]}"; do
          case "$m" in
            curl|tar|jq|unzip|ca-certificates) pkgs+=("$m") ;;
            *) pkgs+=("$m") ;;
          esac
        done
        sudo apt-get install -y "${pkgs[@]}"
      else
        echo "⚠️  sudo not available; please install: ${missing[*]}"
        exit 1
      fi
    else
      echo "⚠️  Cannot auto-install missing deps. Install manually and re-run."
      exit 1
    fi
  fi
}

ensure_deps

# ---------- Install dir pick (prefer user-local; skip pnpm/npm bins) ----------
default_install_dir() {
  if [[ -n "${INSTALL_DIR:-}" ]]; then
    echo "$INSTALL_DIR"; return
  fi

  # Prefer user local bin (no sudo)
  if [[ -d "$HOME/.local/bin" || -w "$HOME" ]]; then
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    if [[ -d "$HOME/.local/bin" && -w "$HOME/.local/bin" ]]; then
      echo "$HOME/.local/bin"; return
    fi
  fi

  # Fallbacks (may need sudo)
  for d in /usr/local/bin /usr/bin; do
    [[ -d "$d" && -w "$d" ]] && { echo "$d"; return; }
  done

  # First writable PATH dir that's not a package-manager sandbox
  IFS=':' read -r -a PATH_DIRS <<< "${PATH:-}"
  for d in "${PATH_DIRS[@]}"; do
    [[ ! -d "$d" || ! -w "$d" ]] && continue
    if echo "$d" | grep -qiE 'pnpm|npm|node|nvm|pyenv|asdf|cargo'; then continue; fi
    echo "$d"; return
  done

  echo "$HOME/.local/bin"
}

# If INSTALL_PATH set, respect it; else compute MANAGED_PATH in INSTALL_DIR
if [[ -n "${INSTALL_PATH:-}" ]]; then
  MANAGED_PATH="$INSTALL_PATH"
  INSTALL_DIR="$(dirname "$INSTALL_PATH")"
else
  INSTALL_DIR="$(default_install_dir)"
  MANAGED_BASENAME="codex-managed"
  MANAGED_PATH="$INSTALL_DIR/$MANAGED_BASENAME"
fi

LINK_CODEX="$INSTALL_DIR/$LINK_NAME"

# ---------- GitHub API ----------
gh_api() {
  local url="$1"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -sfL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$url"
  else
    curl -sfL -H "Accept: application/vnd.github+json" "$url"
  fi
}

# ---------- Matching helpers ----------
match_patterns() {
  if [[ "$OS" == "darwin" && "$ARCH" == "arm64" ]]; then
cat <<EOF
aarch64-apple-darwin
arm64-apple-darwin
darwin-arm64
apple-darwin
darwin
EOF
  elif [[ "$OS" == "darwin" && "$ARCH" == "amd64" ]]; then
cat <<EOF
x86_64-apple-darwin
amd64-apple-darwin
darwin-amd64
apple-darwin
darwin
EOF
  elif [[ "$OS" == "linux" && "$ARCH" == "arm64" ]]; then
cat <<EOF
aarch64-unknown-linux-gnu
linux-arm64
linux-aarch64
linux
EOF
  else
cat <<EOF
x86_64-unknown-linux-gnu
linux-amd64
linux
darwin
EOF
  fi
}

choose_best_asset() {
  local urls; urls="$(cat)"; [[ -z "$urls" ]] && return 1
  local best
  # Prefer OS/ARCH archives FIRST
  while read -r pat; do
    best="$(echo "$urls" | grep -Ei "$pat" | grep -Ei '\.(tar\.gz|tgz|zip)$' | head -n1 || true)"
    [[ -n "$best" ]] && { echo "$best"; return 0; }
  done < <(match_patterns)
  # Then OS/ARCH any
  while read -r pat; do
    best="$(echo "$urls" | grep -Ei "$pat" | head -n1 || true)"
    [[ -n "$best" ]] && { echo "$best"; return 0; }
  done < <(match_patterns)
  # Then plain 'codex' bootstrap
  best="$(echo "$urls" | grep -E '/releases/.*/codex$' | head -n1 || true)"
  [[ -n "$best" ]] && { echo "$best"; return 0; }
  # Fallback
  echo "$urls" | head -n1
}

find_asset_url() {
  local rel="$1"
  local json urls
  json="$(gh_api "https://api.github.com/repos/$REPO/$rel")" || return 1
  urls="$(echo "$json" | grep -Eo '"browser_download_url":\s*"[^"]+"' | cut -d'"' -f4)"
  echo "$urls" | choose_best_asset
}

find_prerelease_asset_url() {
  command -v jq >/dev/null 2>&1 || return 1
  local json urls
  json="$(gh_api "https://api.github.com/repos/$REPO/releases?per_page=30")" || return 1
  urls="$(echo "$json" | jq -r '.[] | select(.prerelease==true) | .assets[].browser_download_url')"
  [[ -z "$urls" ]] && return 1
  echo "$urls" | choose_best_asset
}

# ---------- Write/link helpers (use sudo if needed) ----------
write_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")" 2>/dev/null || true
  if cp "$src" "$dst" 2>/dev/null; then
    return 0
  fi
  if (( AUTO_SUDO == 1 )) && command -v sudo >/dev/null 2>&1; then
    echo "→ Elevating with sudo to write: $dst"
    sudo mkdir -p "$(dirname "$dst")"
    sudo cp "$src" "$dst"
    return 0
  fi
  echo "❌ Cannot write to $(dirname "$dst"). Set INSTALL_DIR to a writable path or enable AUTO_SUDO=1."
  return 1
}

link_file() {
  local target="$1" link="$2"
  rm -f "$link" 2>/dev/null || true
  if ln -s "$target" "$link" 2>/dev/null; then
    return 0
  fi
  if (( AUTO_SUDO == 1 )) && command -v sudo >/dev/null 2>&1; then
    echo "→ Elevating with sudo to link: $link"
    sudo ln -sf "$target" "$link"
    return 0
  fi
  echo "ℹ️  Could not create $link; try: ln -sf \"$target\" \"$link\""
  return 1
}

# ---------- Download & install ----------
download_and_install() {
  local url="$1"
  echo "→ Downloading: $url"
  local tmpdir file target_bin
  tmpdir="$(mktemp -d)"
  trap '[[ -n "${tmpdir:-}" ]] && rm -rf "$tmpdir"' EXIT

  file="$tmpdir/asset"
  curl -sfL "$url" -o "$file"

  mkdir -p "$tmpdir/unpack"
  case "$url" in
    *.tar.gz|*.tgz) tar -xzf "$file" -C "$tmpdir/unpack" ;;
    *.zip)          unzip -q "$file" -d "$tmpdir/unpack" ;;
    *)              cp "$file" "$tmpdir/unpack/$ASSET_NAME_HINT" ;;
  esac

  target_bin=""
  for guess in "$ASSET_NAME_HINT" "codex" "codex-cli"; do
    if found="$(find "$tmpdir/unpack" -maxdepth 2 -type f -iname "$guess" 2>/dev/null | head -n1)"; then
      target_bin="$found"; break
    fi
  done
  if [[ -z "$target_bin" ]]; then
    target_bin="$(find "$tmpdir/unpack" -maxdepth 2 -type f -exec ls -l {} \; 2>/dev/null | awk '{print $5, $9}' | sort -nr | head -n1 | awk '{print $2}')"
  fi
  [[ -z "$target_bin" ]] && { echo "❌ No executable found in asset."; exit 1; }

  chmod +x "$target_bin" || true

  echo "→ Installing managed binary to: $MANAGED_PATH"
  write_file "$target_bin" "$MANAGED_PATH"
  if (( $? != 0 )); then exit 1; fi
  if (( AUTO_SUDO == 1 )) && command -v sudo >/dev/null 2>&1; then sudo chmod +x "$MANAGED_PATH" || true; else chmod +x "$MANAGED_PATH" || true; fi

  # Create/refresh symlink/wrapper
  link_file "$MANAGED_PATH" "$LINK_CODEX" || true
}

# ---------- Main ----------
case "$CHANNEL" in
  stable)  echo "Channel: stable" ;;
  nightly) echo "Channel: nightly (default)" ;;
  *) echo "Usage: $0 [stable|nightly]"; exit 1 ;;
esac

STABLE_REL="releases/latest"
NIGHTLY_REL="releases/tags/nightly"

asset_url=""
if [[ "$CHANNEL" == "nightly" ]]; then
  asset_url="$(find_asset_url "$NIGHTLY_REL" || true)"
  [[ -z "$asset_url" ]] && asset_url="$(find_prerelease_asset_url || true)"
  [[ -z "$asset_url" ]] && asset_url="$(find_asset_url "$STABLE_REL" || true)"
else
  asset_url="$(find_asset_url "$STABLE_REL" || true)"
fi
[[ -z "$asset_url" ]] && { echo "❌ No downloadable asset for $REPO."; exit 1; }

download_and_install "$asset_url"

hash -r 2>/dev/null || true

# Ensure ~/.local/bin is on PATH for this session and give a hint for shells
if [[ "$INSTALL_DIR" == "$HOME/.local/bin" ]]; then
  case ":${PATH:-}:" in
    *:"$HOME/.local/bin":*) : ;;
    *) echo "ℹ️  $HOME/.local/bin is not on PATH. Add this to your shell rc:"
       echo '   export PATH="$HOME/.local/bin:$PATH"'
       ;;
  esac
fi

echo "→ Final check"
if command -v "$LINK_NAME" >/dev/null 2>&1; then
  echo "$LINK_NAME -> $(command -v "$LINK_NAME")"
else
  echo "$LINK_NAME not on PATH (installed to $INSTALL_DIR)."
fi
echo "✅ Managed binary: $MANAGED_PATH"


