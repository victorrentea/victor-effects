#!/bin/bash
# Install victor-effects as a macOS login item (LaunchAgent)
set -e

PLIST_NAME="ro.victorrentea.victor-effects.plist"
DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_SRC="$DIR/$PLIST_NAME"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"

# The plist ships with a placeholder path so the repo carries nobody's home
# directory; the real one is written next to it at install time.
GENERATED="$DIR/.build/$PLIST_NAME"
mkdir -p "$DIR/.build"
sed "s|__START_SH__|$DIR/start.sh|" "$PLIST_SRC" > "$GENERATED"

mkdir -p "$HOME/Library/LaunchAgents"
cp "$GENERATED" "$PLIST_DST"
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"

echo "✅ victor-effects installed as login item"
echo "   Logs: tail -f /tmp/victor-effects.log"
