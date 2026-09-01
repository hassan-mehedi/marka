#!/bin/bash
# Builds Marka.app from the SwiftPM executable.
# Usage: scripts/make-app.sh [debug|release]
# MARKA_ARCH=arm64|x86_64 cross-builds; MARKA_VERSION stamps the bundle version.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_FLAGS=(-c "$CONFIG")
[ -n "${MARKA_ARCH:-}" ] && BUILD_FLAGS+=(--arch "$MARKA_ARCH")

swift build --build-system swiftbuild "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build --build-system swiftbuild "${BUILD_FLAGS[@]}" --show-bin-path)"

APP="$ROOT/build/Marka.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Marka" "$APP/Contents/MacOS/Marka"
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -n "${MARKA_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKA_VERSION" "$APP/Contents/Info.plist"
fi

ICONSET="$(mktemp -d)/Marka.iconset"
mkdir -p "$ICONSET"
PNG="$(mktemp -d)/icon.png"
swift "$ROOT/scripts/make-icon.swift" "$PNG"
for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    set -- $pair
    sips -z "$1" "$1" "$PNG" --out "$ICONSET/icon_$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Marka.icns"

# Ad-hoc signature: without it macOS refuses to launch an unsigned bundle.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: codesign failed, app may not launch"

echo "built $APP"
