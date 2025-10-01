#!/usr/bin/env bash
set -euo pipefail

REPO="ClementTsang/bottom"
APP="bottom"          # package name in the .deb filename
BIN="btm"             # installed binary name

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

# Detect Debian and require root (or sudo available)
if ! grep -qi debian /etc/os-release; then
  echo "This installer targets Debian. Aborting."
  exit 1
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if need_cmd sudo; then
    SUDO="sudo"
  else
    echo "Please run as root or install sudo."
    exit 1
  fi
fi

# Ensure curl and jq exist
if ! need_cmd curl || ! need_cmd jq; then
  echo "Installing prerequisites: curl jq"
  $SUDO apt-get update -qq
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq curl jq >/dev/null
fi

# Map uname -m to Debian arch suffix in release asset names
uname_m=$(uname -m)
case "$uname_m" in
  x86_64)   ARCH="amd64" ;;
  aarch64)  ARCH="arm64" ;;
  arm64)    ARCH="arm64" ;; # just in case
  *)
    echo "Unsupported architecture: $uname_m (supported: x86_64, aarch64)."
    exit 2
    ;;
esac

echo "Detected architecture: $ARCH"

API_URL="https://api.github.com/repos/${REPO}/releases/latest"

echo "Querying latest release metadata…"
json="$(curl -fsSL "$API_URL")" || {
  echo "Failed to query GitHub API. Are you offline or rate-limited?"
  exit 3
}

tag="$(echo "$json" | jq -r .tag_name)"
if [ -z "$tag" ] || [ "$tag" = "null" ]; then
  echo "Could not determine latest tag from GitHub."
  exit 3
fi

# Prefer glibc .deb (without 'musl' in the name); fall back to musl if necessary.
asset_url="$(
  echo "$json" \
  | jq -r --arg arch "$ARCH" '
      .assets
      | map(select(.name | test("^'"$APP"'_.*_" + $arch + "\\.deb$") and (contains("musl")|not)))
      | (.[0] // empty) .browser_download_url
    '
)"
if [ -z "$asset_url" ] || [ "$asset_url" = "null" ]; then
  asset_url="$(
    echo "$json" \
    | jq -r --arg arch "$ARCH" '
        .assets
        | map(select(.name | test("^'"$APP"'-?musl?_.*_" + $arch + "\\.deb$")))
        | (.[0] // empty) .browser_download_url
      '
  )"
fi

if [ -z "$asset_url" ] || [ "$asset_url" = "null" ]; then
  echo "Could not find a .deb asset for architecture '$ARCH' in release $tag."
  exit 4
fi

file="/tmp/${APP}_${tag}_${ARCH}.deb"
echo "Downloading $asset_url → $file"
curl -fL --progress-bar -o "$file" "$asset_url"

echo "Installing $file"
set +e
$SUDO dpkg -i "$file"
rc=$?
set -e
if [ $rc -ne 0 ]; then
  echo "Resolving dependencies…"
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get -y -qq -f install
  echo "Retrying installation…"
  $SUDO dpkg -i "$file"
fi

echo "Verifying install:"
if need_cmd "$BIN"; then
  "$BIN" --version || true
  echo
  echo "✅ Installed. Start with:  $BIN"
else
  echo "Installation finished but '$BIN' not found on PATH."
  exit 5
fi
