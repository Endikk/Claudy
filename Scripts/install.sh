#!/bin/bash
#
# Installe la dernière release de Claudy dans /Applications :
#
#   curl -fsSL https://raw.githubusercontent.com/Endikk/Claudy/main/Scripts/install.sh | bash
#
# Claudy n'est pas notarisé (distribution gratuite, sans compte Apple Developer) :
# le script retire la quarantaine posée au téléchargement, sinon Gatekeeper refuse
# de lancer l'app. Si tu préfères ne pas lever la quarantaine, clone le dépôt et
# compile toi-même : ./Scripts/build-app.sh --install

set -euo pipefail

REPO="Endikk/Claudy"

echo "▸ recherche de la dernière release…"
url="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*\.zip"' \
    | head -1 \
    | grep -o 'https://[^"]*')" || url=""

if [[ -z "$url" ]]; then
    echo "aucune release trouvée pour $REPO." >&2
    echo "installation depuis les sources (nécessite Xcode) :" >&2
    echo "  git clone https://github.com/$REPO.git && cd Claudy && ./Scripts/build-app.sh --install" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "▸ téléchargement : $url"
curl -fsSL "$url" -o "$tmp/Claudy.zip"
ditto -x -k "$tmp/Claudy.zip" "$tmp"
[[ -d "$tmp/Claudy.app/Contents" ]] || { echo "archive inattendue (pas de Claudy.app)" >&2; exit 1; }

# Quarantaine : voir l'en-tête du script.
xattr -dr com.apple.quarantine "$tmp/Claudy.app" 2>/dev/null || true

pkill -x Claudy 2>/dev/null || true
if ! { rm -rf /Applications/Claudy.app && ditto "$tmp/Claudy.app" /Applications/Claudy.app; } 2>/dev/null; then
    echo "écriture dans /Applications refusée — relance avec sudo :" >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/Scripts/install.sh | sudo bash" >&2
    exit 1
fi

open /Applications/Claudy.app
echo "▸ Claudy installé dans /Applications et lancé"
