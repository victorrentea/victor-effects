#!/bin/bash
# Build /Applications/Victor Effects.app from this checkout.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

APP_NAME="Victor Effects"
BUNDLE_ID="ro.victorrentea.victor-effects"
APP_DIR="/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BUILD_CONFIG="release"

BUILD_TIMESTAMP=$(date "+%b %-d, %H:%M")
sed -i '' "s/static let BUILD_TIME = .*/static let BUILD_TIME = \"$BUILD_TIMESTAMP\"/" "$DIR/Sources/VictorEffects/MenuBar.swift"
echo "Build timestamp: $BUILD_TIMESTAMP"

echo "Building VictorEffects..."
swift build -c "$BUILD_CONFIG"
echo "VictorEffects built."

# NOTE: no sounds-dereference step here, unlike victor-macos-addons. The
# soundboard mp3s are NOT a bundle resource of this app — they are read live from
# EffectsConfig.soundsDir, so a changed mp3 needs no rebuild and no symlink ever
# reaches the .build bundle.

echo "Building $APP_NAME.app..."

# Convert the 💥 PNG (tools/make-icon.swift) to ICNS
ICONSET=$(mktemp -d)/icon.iconset
mkdir -p "$ICONSET"
SRC_ICON="$DIR/Sources/VictorEffects/Resources/icon_explosion.png"
for SIZE in 16 32 64 128 256 512; do
    sips -z $SIZE $SIZE "$SRC_ICON" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null 2>&1
    DOUBLE=$((SIZE * 2))
    if [ $DOUBLE -le 1024 ]; then
        sips -z $DOUBLE $DOUBLE "$SRC_ICON" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null 2>&1
    fi
done
ICNS_FILE="$DIR/Sources/VictorEffects/Resources/AppIcon.icns"
iconutil -c icns "$ICONSET" -o "$ICNS_FILE"
rm -rf "$(dirname "$ICONSET")"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ICNS_FILE" "$RESOURCES/AppIcon.icns"

# The release binary, never a debug-run artifact: debug artifacts live at a
# different path and macOS records TCC grants per path+identity.
cp "$DIR/.build/arm64-apple-macosx/$BUILD_CONFIG/VictorEffects" "$MACOS/$APP_NAME"

# NOTE: Bundle.module resources are resolved at runtime from the generated
# accessor's ABSOLUTE ".build/arm64-apple-macosx/$BUILD_CONFIG/VictorEffects_VictorEffects.bundle"
# path. We intentionally do NOT copy that bundle into the .app: anything at the
# .app ROOT (outside Contents/) is "unsealed content" that makes codesign fall
# back to an ad-hoc signature, which BREAKS TCC persistence (Accessibility and
# Screen Recording re-prompt on every rebuild). The trade-off: always deploy
# from this permanent checkout, and do not `swift package clean`.

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Victor Effects listens for the right ⌥ key and puts the mouse in effects like the fire cursor.</string>
</dict>
</plist>
PLIST

# Sign with a stable identity when one is available, so TCC grants survive a
# rebuild. Example: export CODESIGN_IDENTITY="Apple Development: You (TEAMID)"
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    # grep, not rg: this runs under bash where `rg` may be a zsh-only shim, and a
    # silently failing lookup falls through to the ad-hoc branch — which is
    # exactly what revokes Accessibility and kills the hotkeys after a rebuild.
    for CANDIDATE in "Victor Effects Local Code Signing" "Victor Addons Local Code Signing"; do
        if security find-identity -v -p codesigning "$HOME/Library/Keychains/login.keychain-db" | grep -Fq "$CANDIDATE"; then
            SIGNING_IDENTITY="$CANDIDATE"
            break
        fi
    done
fi

if [ -n "$SIGNING_IDENTITY" ]; then
    codesign --force --sign "$SIGNING_IDENTITY" "$APP_DIR"
    echo "Signed with: $SIGNING_IDENTITY"
else
    echo "⚠️  No code signing identity; using ad-hoc signature (Accessibility may re-prompt after updates)."
    codesign --force --sign - "$APP_DIR"
fi

echo "✅ Installed $APP_DIR"
echo "   Restart it with: pkill -f \"$APP_NAME\"; open \"$APP_DIR\""
