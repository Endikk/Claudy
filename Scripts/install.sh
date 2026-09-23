#!/bin/bash
#
# Installs the latest Claudy release into /Applications:
#
#   curl -fsSL https://raw.githubusercontent.com/Endikk/Claudy/main/Scripts/install.sh | bash
#
# Claudy is not notarised (free distribution, no Apple Developer account): the
# script removes the quarantine flag set on download, otherwise Gatekeeper refuses
# to launch the app. If you prefer not to lift the quarantine, clone the repository
# and build it yourself: ./Scripts/build-app.sh --install

set -euo pipefail

REPO="Endikk/Claudy"

echo "▸ looking up the latest release…"
url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*\.zip"' \
    | head -1 \
    | grep -o 'https://[^"]*')" || url=""

if [[ -z "$url" ]]; then
    echo "no release found for $REPO." >&2
    echo "install from source (requires Xcode):" >&2
    echo "  git clone https://github.com/$REPO.git && cd Claudy && ./Scripts/build-app.sh --install" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "▸ downloading: $url"
curl -fsSL "$url" -o "$tmp/Claudy.zip"
ditto -x -k "$tmp/Claudy.zip" "$tmp"
[[ -d "$tmp/Claudy.app/Contents" ]] || { echo "unexpected archive (no Claudy.app inside)" >&2; exit 1; }

# Quarantine: see the header of this script.
xattr -dr com.apple.quarantine "$tmp/Claudy.app" 2>/dev/null || true

pkill -x Claudy 2>/dev/null || true
if ! { rm -rf /Applications/Claudy.app && ditto "$tmp/Claudy.app" /Applications/Claudy.app; } 2>/dev/null; then
    echo "writing to /Applications was refused, run again with sudo:" >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/Scripts/install.sh | sudo bash" >&2
    exit 1
fi

open /Applications/Claudy.app
echo "▸ Claudy installed into /Applications and launched"
