#!/usr/bin/env bash
#
# Builds MacZones.app (universal: arm64 + x86_64), ad-hoc signs it and produces
# a .zip and a .dmg under dist/.
#
# Usage: scripts/build-app.sh [version]
#        VERSION env var is also honoured. Leading "v" is stripped.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MacZones"
BUNDLE_ID="de.projectmakers.maczones"
DIST_DIR="dist"

RAW_VERSION="${1:-${VERSION:-0.0.0-dev}}"
VERSION="${RAW_VERSION#v}"

echo "==> Building $APP_NAME $VERSION (universal)"
swift build -c release --arch arm64 --arch x86_64

BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
BIN_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -f "$BIN_PATH" ]]; then
    echo "!! Built binary not found at $BIN_PATH" >&2
    exit 1
fi

APP="$DIST_DIR/$APP_NAME.app"
echo "==> Assembling app bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License — ProjectMakers</string>
</dict>
</plist>
PLIST

# Signing identity: a stable self-signed certificate (so the Accessibility
# permission survives updates). Falls back to ad-hoc ("-") for local dev.
IDENTITY="${SIGN_IDENTITY:--}"

echo "==> Signing with identity: $IDENTITY"
if [[ -n "${SIGN_KEYCHAIN:-}" ]]; then
    codesign --force --deep --keychain "$SIGN_KEYCHAIN" --sign "$IDENTITY" "$APP"
else
    codesign --force --deep --sign "$IDENTITY" "$APP"
fi

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP" && echo "   signature ok"
codesign -dvv "$APP" 2>&1 | grep -E "Authority|Identifier|TeamIdentifier" || true

echo "==> Creating archives"
( cd "$DIST_DIR" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME.zip" )

# DMG (best effort — does not fail the build if hdiutil hiccups in CI)
if hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DIST_DIR/$APP_NAME.dmg"; then
    echo "   dmg created"
else
    echo "   (dmg creation skipped)"
fi

echo "==> Done:"
ls -la "$DIST_DIR"
