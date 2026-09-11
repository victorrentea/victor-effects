#!/bin/bash
# Launch Victor Effects (menu bar + overlay + HTTP on 55124)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

LOG=/tmp/victor-effects.log
echo "$(date '+%H:%M:%S') Starting Victor Effects..." >> "$LOG"

APP="/Applications/Victor Effects.app"
if [ ! -x "$APP/Contents/MacOS/Victor Effects" ]; then
    echo "$(date '+%H:%M:%S') Victor Effects not installed — run: ./build-app.sh" >> "$LOG"
    exit 1
fi

# No `adb reverse` here: the tablet still talks to victor-macos-addons on 55123,
# which proxies the effect and sound routes over to this app on 55124.

# `open`, NOT the bundle binary. macOS keys an Accessibility / Screen Recording
# grant to a bundle identifier only for a process LaunchServices launched; a
# process that exec'd its own Mach-O is filed by PATH instead, as a second,
# unrelated app that happens to share a name and gets the generic `exec` icon.
# Ticking its box in System Settings then grants the wrong row, which is exactly
# how this app spent a day with two dead permissions. See docs/deployment.md.
#
# No `-W`: `open` hands the app to launchd and exits, so `pgrep -f "Victor
# Effects"` finds exactly one process and `pkill -f "Victor Effects"` still means
# the app. The LaunchAgent job simply completes; the app keeps running under
# launchd, which is what a LaunchServices app looks like.
#
# `--env` because LaunchServices does not pass this shell's environment through.
exec /usr/bin/open --env "VICTOR_EFFECTS_ROOT=$DIR" -a "$APP"
