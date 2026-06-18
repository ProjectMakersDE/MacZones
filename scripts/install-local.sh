#!/usr/bin/env bash
#
# Builds MacZones (signed with the local stable identity, if set up) and
# installs it into /Applications, then launches it. Mirrors how the STT-Bar tool
# is installed locally.
#
# Run scripts/setup-local-signing.sh once beforehand so the build is signed with
# the same certificate as the GitHub releases (keeps the Accessibility
# permission across updates). Without it, the build is ad-hoc signed.
#
# Usage: scripts/install-local.sh [version]
#
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-0.0.0-local}"
KC="$HOME/Library/Keychains/maczones-signing.keychain-db"
PW_FILE="$HOME/.config/maczones/signing-keychain.pw"
APP="/Applications/MacZones.app"

if [[ -f "$KC" && -f "$PW_FILE" ]]; then
    security unlock-keychain -p "$(cat "$PW_FILE")" "$KC"
    export SIGN_IDENTITY="MacZones Self-Signed"
    export SIGN_KEYCHAIN="$KC"
    echo "==> Signing with stable identity: $SIGN_IDENTITY"
else
    echo "==> No local signing keychain found — building ad-hoc."
    echo "    (Run scripts/setup-local-signing.sh for a permission-stable install.)"
fi

./scripts/build-app.sh "$VERSION"

echo "==> Quitting any running MacZones"
osascript -e 'quit app "MacZones"' >/dev/null 2>&1 || true

echo "==> Installing to $APP"
rm -rf "$APP"
ditto "dist/MacZones.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Verifying signature"
codesign -dvv "$APP" 2>&1 | grep -E "Authority|Identifier" || true

echo "==> Launching"
open "$APP"
echo "Installed MacZones $VERSION to /Applications."
