#!/bin/bash
#
# Builds Claudy.app in Release (universal arm64 + x86_64 binary).
#
#   ./Scripts/build-app.sh              → build/Claudy.app
#   ./Scripts/build-app.sh --install    → installs into /Applications and launches it
#   ./Scripts/build-app.sh --zip        → dist/Claudy-<version>.zip (release artefact)
#
# The version comes from MARKETING_VERSION in the Xcode project, the single source of truth.

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
        *) echo "unknown option: $arg (expected: --install, --zip)" >&2; exit 1 ;;
    esac
done

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild not found: install Xcode, then run again." >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$BUILD"

echo "▸ xcodebuild (Release, universal)"
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

# ── Post-build checks ─────────────────────────────────────────────────────────
archs="$(lipo -archs "$APP/Contents/MacOS/Claudy")"
if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
    echo "binary is not universal: $archs" >&2
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
    # ditto keeps the signature and metadata, unlike zip -r.
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "▸ $ZIP"
fi

if $install; then
    [[ -d "$APP/Contents" ]] || { echo "invalid bundle: $APP" >&2; exit 1; }
    # A copy that is already running would keep the old binary in memory.
    pkill -x Claudy 2>/dev/null || true
    rm -rf /Applications/Claudy.app
    ditto "$APP" /Applications/Claudy.app
    open /Applications/Claudy.app
    echo "▸ installed into /Applications and launched"
fi
