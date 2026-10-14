#!/bin/bash
# Publish a GitHub release that install.sh can fetch: a universal (arm64 +
# x86_64), ad-hoc signed "Victor Effects.app", zipped, plus the starter pack
# inside it. Run from a clean checkout of master on the maintainer's Mac:
#
#   tools/release.sh            # tag = v<yyyy.mm.dd-HHMM>
#   tools/release.sh v1.2.0     # explicit tag
#
# Ad-hoc, not the maintainer's local identity: a self-signed certificate means
# nothing on anyone else's Mac, and an ad-hoc signature is what the first-launch
# permission prompts accept. Not notarized — install.sh downloads with curl,
# which sets no quarantine flag, so Gatekeeper never asks.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

TAG="${1:-v$(date +%Y.%m.%d-%H%M)}"
DIST="$DIR/dist"
APP="$DIST/Victor Effects.app"
ZIP="$DIST/Victor-Effects.zip"

[ -z "$(git status --porcelain -- Sources starter-pack Package.swift build-app.sh)" ] \
    || { echo "Uncommitted changes in Sources/starter-pack — commit first." >&2; exit 1; }

# Nothing third-party may ride along: the starter pack must be fully credited.
python3 tools/check-starter-pack.py
python3 tools/copyright-guard.py check

rm -rf "$DIST"; mkdir -p "$DIST"
# build-app.sh stamps MenuBar.BUILD_TIME in place; put the file back afterwards
# by copy, never `git checkout` (other sessions may have edits in this tree).
cp Sources/VictorEffects/MenuBar.swift "$DIST/MenuBar.swift.keep"
UNIVERSAL=1 CODESIGN_IDENTITY=- APP_DIR="$APP" ./build-app.sh
cp "$DIST/MenuBar.swift.keep" Sources/VictorEffects/MenuBar.swift
codesign --verify --strict --deep "$APP"
lipo -archs "$APP/Contents/MacOS/Victor Effects"
ditto -c -k --keepParent "$APP" "$ZIP"
ls -lh "$ZIP"

gh release create "$TAG" "$ZIP" install.sh \
    --title "Victor Effects $TAG" \
    --notes "Install or update: \`curl -fsSL https://raw.githubusercontent.com/victorrentea/victor-effects/main/install.sh | bash\`

Universal app (Apple silicon + Intel), macOS 13+, ad-hoc signed. Includes the free starter soundboard (starter-pack/CREDITS.md)."
echo "✅ Released $TAG"
