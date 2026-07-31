#!/bin/bash
#
# Construit Claudy.app en Release (binaire universel arm64 + x86_64).
#
#   ./Scripts/build-app.sh              → build/Claudy.app
#   ./Scripts/build-app.sh --install    → installe dans /Applications et lance
#   ./Scripts/build-app.sh --zip        → dist/Claudy-<version>.zip (artefact de release)
#
# La version vient de MARKETING_VERSION dans le projet Xcode — unique source de vérité.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Claudy.app"

install=false
zip=false
for arg in "$@"; do
    case "$arg" in
        --install) install=true ;;
        --zip) zip=true ;;
        *) echo "option inconnue : $arg (attendu : --install, --zip)" >&2; exit 1 ;;
    esac
done

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild introuvable — installe Xcode puis relance." >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$BUILD"

echo "▸ xcodebuild (Release, universel)"
xcodebuild \
    -project "$ROOT/Claudy.xcodeproj" \
    -scheme Claudy \
    -configuration Release \
    -derivedDataPath "$BUILD/DerivedData" \
    -destination 'generic/platform=macOS' \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    -quiet build

ditto "$BUILD/DerivedData/Build/Products/Release/Claudy.app" "$APP"

# ── Vérifications post-build ──────────────────────────────────────────────────
archs="$(lipo -archs "$APP/Contents/MacOS/Claudy")"
if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
    echo "binaire non universel : $archs" >&2
    exit 1
fi
codesign --verify --deep "$APP"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

VERSION="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
echo "▸ $APP (v$VERSION, $archs)"

if $zip; then
    mkdir -p "$ROOT/dist"
    ZIP="$ROOT/dist/Claudy-$VERSION.zip"
    rm -f "$ZIP"
    # ditto préserve la signature et les métadonnées, contrairement à zip -r.
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "▸ $ZIP"
fi

if $install; then
    [[ -d "$APP/Contents" ]] || { echo "bundle invalide : $APP" >&2; exit 1; }
    # Une copie déjà en cours d'exécution garderait l'ancien binaire en mémoire.
    pkill -x Claudy 2>/dev/null || true
    rm -rf /Applications/Claudy.app
    ditto "$APP" /Applications/Claudy.app
    open /Applications/Claudy.app
    echo "▸ installé dans /Applications et lancé"
fi
