#!/bin/bash
# Install Victor Effects on this Mac — one command, no Xcode needed:
#
#   curl -fsSL https://raw.githubusercontent.com/victorrentea/victor-effects/main/install.sh | bash
#
# What it does, in order (every step is safe to re-run):
#   1. downloads the latest release (a universal app: Apple silicon + Intel)
#   2. quits a running copy and installs it to /Applications (~/Applications
#      when /Applications is not writable)
#   3. registers a login item (LaunchAgent) so it starts with the Mac
#   4. starts it, and checks it answers on http://127.0.0.1:55124/ping
#   5. tells you the two permissions only YOU can grant (macOS does not let any
#      script or agent tick them) and opens the right System Settings pane
#
# Options:
#   --from-source     build from a clone of this repo instead (needs Xcode or
#                     the Command Line Tools: xcode-select --install)
#   --no-login-item   do not start it at login
#   --uninstall       remove the app, the login item and ~/.victor-effects
#   --version <tag>   install a specific release instead of the latest
#
# Agents installing this for a user: run it, then read the last lines it
# prints — the permissions step needs the human, everything else does not.
set -euo pipefail

REPO="victorrentea/victor-effects"
APP_NAME="Victor Effects"
BUNDLE_ID="ro.victorrentea.victor-effects"
ZIP_NAME="Victor-Effects.zip"
PORT=55124
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

FROM_SOURCE=0
LOGIN_ITEM=1
UNINSTALL=0
VERSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --from-source) FROM_SOURCE=1 ;;
        --no-login-item) LOGIN_ITEM=0 ;;
        --uninstall) UNINSTALL=1 ;;
        --version) VERSION="${2:?--version needs a tag}"; shift ;;
        -h|--help) sed -n '2,24p' "$0" 2>/dev/null || true; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m⚠️  %s\033[0m\n' "$*"; }
die()  { printf '\033[31m❌ %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Victor Effects is a macOS app."
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 13 ] || die "Needs macOS 13 (Ventura) or later; this is $(sw_vers -productVersion)."

quit_running() {
    if pgrep -f "$APP_NAME.app/Contents/MacOS" >/dev/null 2>&1; then
        say "Quitting the running copy"
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -f "$APP_NAME.app/Contents/MacOS" >/dev/null 2>&1 || break
            sleep 0.5
        done
        pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
    fi
}

if [ "$UNINSTALL" = 1 ]; then
    quit_running
    launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT"
    rm -rf "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"
    rm -rf "$HOME/.victor-effects"
    tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
    say "Uninstalled."
    exit 0
fi

# Where the app goes: /Applications when we may write there, else ~/Applications.
DEST_DIR="/Applications"
if [ ! -w "$DEST_DIR" ]; then
    DEST_DIR="$HOME/Applications"
    mkdir -p "$DEST_DIR"
fi
APP="$DEST_DIR/$APP_NAME.app"

WORK=$(mktemp -d -t victor-effects-install)
trap 'rm -rf "$WORK"' EXIT

if [ "$FROM_SOURCE" = 1 ]; then
    xcrun --find swift >/dev/null 2>&1 \
        || die "No Swift toolchain. Run: xcode-select --install   (then re-run this script)"
    SRC="$HOME/.victor-effects/src"
    if [ -d "$SRC/.git" ]; then
        say "Updating the clone in $SRC"
        git -C "$SRC" pull --ff-only --quiet
    else
        say "Cloning $REPO into $SRC"
        mkdir -p "$(dirname "$SRC")"
        git clone --quiet --depth 1 "https://github.com/$REPO.git" "$SRC"
    fi
    say "Building (2–4 minutes the first time)"
    quit_running
    # Ad-hoc signed: grants must be given again after every rebuild.
    (cd "$SRC" && SKIP_TESTS=1 CODESIGN_IDENTITY=- APP_DIR="$APP" ./build-app.sh >"$WORK/build.log" 2>&1) \
        || { tail -30 "$WORK/build.log"; die "Build failed (full log above)."; }
else
    if [ -n "$VERSION" ]; then
        URL="https://github.com/$REPO/releases/download/$VERSION/$ZIP_NAME"
    else
        URL="https://github.com/$REPO/releases/latest/download/$ZIP_NAME"
    fi
    # Test hook: a zip served from elsewhere (a build not released yet).
    URL="${VICTOR_EFFECTS_ZIP_URL:-$URL}"
    say "Downloading $URL"
    curl -fL --progress-bar -o "$WORK/$ZIP_NAME" "$URL" \
        || die "Download failed. No release yet? Try: bash install.sh --from-source"
    ditto -x -k "$WORK/$ZIP_NAME" "$WORK/unzipped"
    [ -d "$WORK/unzipped/$APP_NAME.app" ] || die "The download does not contain $APP_NAME.app"
    quit_running
    rm -rf "$APP"
    ditto "$WORK/unzipped/$APP_NAME.app" "$APP"
fi
# curl sets no quarantine flag, but a zip fetched by a browser would: clear it so
# Gatekeeper does not refuse an app that is not notarized.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
say "Installed $APP"

if [ "$LOGIN_ITEM" = 1 ]; then
    # `open -a`, never the binary: macOS files a binary started by path as a
    # second, unrelated app, and the permissions granted to the real one do
    # not apply to it.
    mkdir -p "$(dirname "$LAUNCH_AGENT")"
    cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array><string>/usr/bin/open</string><string>-a</string><string>$APP</string></array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
    launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT" 2>/dev/null || true
    say "Login item registered ($LAUNCH_AGENT)"
fi

# The login item's RunAtLoad launches it already; a second `open` while that
# launch is still in flight makes the app relaunch itself (a reopen = restart,
# by design). So give the login item up to 10 s, and open only if it did not.
STARTED=0
if [ "$LOGIN_ITEM" = 1 ]; then
    for _ in $(seq 1 20); do
        pgrep -f "$APP_NAME.app/Contents/MacOS" >/dev/null 2>&1 && { STARTED=1; break; }
        sleep 0.5
    done
fi
if [ "$STARTED" = 0 ]; then
    say "Starting $APP_NAME"
    open -a "$APP"
fi
UP=0
# Up to 60 s: right after a boot, or on a slow disk, a first launch can take
# most of a minute (measured on a fresh VM).
for _ in $(seq 1 120); do
    if curl -fs -m 1 "http://127.0.0.1:$PORT/ping" >/dev/null 2>&1; then UP=1; break; fi
    sleep 0.5
done
if [ "$UP" != 1 ]; then
    warn "Installed and started, but it has not answered on port $PORT within 60 s yet."
    warn "It may still be starting (first launch after a boot is slow). Check: curl http://127.0.0.1:$PORT/ping — log: /tmp/victor-effects.log"
fi
curl -fs -m 2 "http://127.0.0.1:$PORT/effect/confetti" >/dev/null 2>&1 || true
say "Running: the menu bar shows an fx icon and confetti just fell on the screen."

# A grant counts as given only when /state says true — an unanswered or
# older /state is "missing", never "granted".
STATE=""
for _ in $(seq 1 20); do
    STATE=$(curl -fs -m 3 "http://127.0.0.1:$PORT/state" || true)
    printf '%s' "$STATE" | grep -q '"permissions"' && break
    sleep 0.5
done
grant_missing() { ! printf '%s' "$STATE" | grep -q "\"$1\":true"; }

echo
if grant_missing accessibility || grant_missing screenRecording; then
    echo "────────────────────────────────────────────────────────────────────"
    echo " ONE MANUAL STEP — macOS lets only you grant these (no script can):"
    if grant_missing accessibility; then
        echo "  • Accessibility    → for the hotkeys: hold RIGHT ⌘ = soundboard, ⌃W = whip"
    fi
    if grant_missing screenRecording; then
        echo "  • Screen Recording → for the effects that bend what is on screen"
    fi
    echo " System Settings › Privacy & Security › <each one> › switch on"
    echo " \"$APP_NAME\", then quit it from its menu (fx › Quit) and reopen it."
    echo " Everything else already works without them."
    echo "────────────────────────────────────────────────────────────────────"
    if grant_missing accessibility; then
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
    else
        open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null || true
    fi
else
    say "Permissions: both granted."
fi

cat <<EOF

Try it:
  curl http://127.0.0.1:$PORT/effect/fireworks      # any effect, from anywhere
  hold the RIGHT ⌘ key                               # the soundboard panel
Your own sounds: put NN_name.mp3 files plus a tiles.json in a folder and point
"soundsDir" at it in ~/.victor-effects/config.json (README: "Bring your own sounds").
Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash -s -- --uninstall
EOF
