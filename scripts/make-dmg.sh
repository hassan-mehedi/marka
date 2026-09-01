#!/bin/bash
# Builds Marka.app for one architecture and wraps it in a compressed dmg.
# Usage: scripts/make-dmg.sh [version] [arch]
set -euo pipefail

VERSION="${1:-dev}"
VERSION="${VERSION#v}"
ARCH="${2:-$(uname -m)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MARKA_ARCH="$ARCH" MARKA_VERSION="$VERSION" "$ROOT/scripts/make-app.sh" release

STAGE="$(mktemp -d)/Marka"
mkdir -p "$STAGE"
cp -R "$ROOT/build/Marka.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$ROOT/build/Marka-$VERSION-$ARCH.dmg"
rm -f "$DMG"
hdiutil create -volname "Marka" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "built $DMG"
