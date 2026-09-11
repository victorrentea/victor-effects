#!/bin/bash
# Launch Victor Effects (menu bar + overlay + HTTP on 55124)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

LOG=/tmp/victor-effects.log
echo "$(date '+%H:%M:%S') Starting Victor Effects..." >> "$LOG"

BUNDLE_BIN="/Applications/Victor Effects.app/Contents/MacOS/Victor Effects"
if [ ! -x "$BUNDLE_BIN" ]; then
    echo "$(date '+%H:%M:%S') Victor Effects not installed — run: ./build-app.sh" >> "$LOG"
    exit 1
fi

# No `adb reverse` here: the tablet still talks to victor-macos-addons on 55123,
# which proxies the effect and sound routes over to this app on 55124.
export VICTOR_EFFECTS_ROOT="$DIR"

exec "$BUNDLE_BIN" >> "$LOG" 2>&1
