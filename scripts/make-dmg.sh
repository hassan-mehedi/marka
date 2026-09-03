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

# Signed builds also get the dmg signed, notarized, and stapled when the
# notary credentials are present.
if [ -n "${MARKA_SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$MARKA_SIGN_IDENTITY" "$DMG"
    if [ -n "${MARKA_APPLE_ID:-}" ] && [ -n "${MARKA_TEAM_ID:-}" ] && [ -n "${MARKA_APP_PASSWORD:-}" ]; then
        xcrun notarytool submit "$DMG" --wait \
            --apple-id "$MARKA_APPLE_ID" --team-id "$MARKA_TEAM_ID" --password "$MARKA_APP_PASSWORD"
        xcrun stapler staple "$DMG"
    fi
fi
echo "built $DMG"
