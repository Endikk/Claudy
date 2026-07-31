#!/bin/bash
#
# Construit Claudy.app en Release.
#
#   ./Scripts/build-app.sh              → build/Claudy.app
#   ./Scripts/build-app.sh --install    → installe dans /Applications et lance
#
# Passe par xcodebuild quand il fonctionne, et retombe sinon sur une compilation
# swiftc + assemblage manuel du bundle — utile tant que le contenu système de Xcode
# n'est pas à jour (« xcodebuild failed to load a required plug-in »).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Claudy.app"

BUNDLE_ID="com.claudy.Claudy"
VERSION="1.0"
MIN_MACOS="13.0"

install=false
[[ "${1:-}" == "--install" ]] && install=true

rm -rf "$APP"
mkdir -p "$BUILD"

# ── 1. Chemin normal : xcodebuild ─────────────────────────────────────────────
if xcodebuild -version >/dev/null 2>&1; then
    echo "▸ xcodebuild (Release)"
    xcodebuild \
        -project "$ROOT/Claudy.xcodeproj" \
        -scheme Claudy \
        -configuration Release \
        -derivedDataPath "$BUILD/DerivedData" \
        build >/dev/null

    cp -R "$BUILD/DerivedData/Build/Products/Release/Claudy.app" "$APP"

# ── 2. Repli : swiftc + bundle assemblé à la main ─────────────────────────────
else
    echo "▸ xcodebuild indisponible — repli sur swiftc"
    echo "  (pour le réparer une fois pour toutes : sudo xcodebuild -runFirstLaunch)"

    SDK="$(xcrun --show-sdk-path --sdk macosx)"
    ARCH="$(uname -m)"

    mkdir -p "$APP/Contents/MacOS"

    xcrun swiftc \
        -sdk "$SDK" \
        -target "$ARCH-apple-macos$MIN_MACOS" \
        -O -whole-module-optimization \
        $(find "$ROOT/Claudy" -name '*.swift') \
        -o "$APP/Contents/MacOS/Claudy"

    cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Claudy</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Claudy</string>
  <key>CFBundleDisplayName</key><string>Claudy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

    # Signature ad hoc : suffisante pour lancer localement.
    # « Lancer au démarrage » (SMAppService) exige, lui, une vraie identité.
    codesign --force --sign - "$APP"
fi

echo "▸ $APP"

if $install; then
    # Une copie déjà en cours d'exécution garderait l'ancien binaire en mémoire.
    pkill -x Claudy 2>/dev/null || true
    rm -rf /Applications/Claudy.app
    cp -R "$APP" /Applications/Claudy.app
    open /Applications/Claudy.app
    echo "▸ installé dans /Applications et lancé"
fi
