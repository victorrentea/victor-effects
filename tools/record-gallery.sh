#!/bin/bash
# record-gallery.sh — record every overlay effect over a believable backdrop and
# assemble one gallery video.
#
# The whole pipeline in one re-runnable command, so the same thing a skill drives
# by hand can later be driven by launchd at 03:00 with nobody in the chair.
#
# Read `.claude/skills/effects-gallery/SKILL.md` for the why behind the numbers.
# The short version of the constraints this script is shaped by:
#
#   - **The effect list is not written down here.** It is parsed out of
#     `fireEffect`'s switch in `EffectsEngine.swift`, the same source
#     `SoundEffectMapDriftTests` parses, because this repo has already paid for
#     keeping a second copy of that list (see the ⭐ catalogue in CLAUDE.md).
#   - **Durations are not written down here either.** An effect's real length
#     lives in its `trackEffect(duration:)` call; `GET /state` reports it as
#     `activeEffects` while it runs, so the recorder stops when the effect stops
#     rather than after a guessed sleep.
#   - **Capture is ScreenCaptureKit** (`tools/gallery-recorder.swift`), because
#     ffmpeg's avfoundation screen device no longer exists on this macOS and
#     `screencapture -v` refuses to run from a script.
#   - **The screen is taken while this runs**, so it re-execs itself under the 🔒
#     hands-off locks and holds the display awake with caffeinate.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${VICTOR_EFFECTS_PORT:-55124}"
BASE="http://127.0.0.1:$PORT"

OUT="$REPO/.build/gallery"
MODE="display"                 # display | window
WIDTH=1440
FPS=30
SETTLE=1.0                     # let the screen go quiet before the recorder starts
WARMUP=0.8                     # SCK needs a beat between startCapture and the first frame
MIN_CLIP=3.0                   # a 1.4 s effect still needs to be watchable
MAX_CLIP=16                    # nothing in the catalogue legitimately runs longer
ONLY=""
EXTRA_SKIP=""
BACKDROP_FILE="$REPO/tools/gallery-assets/Backdrop.java"
BACKDROP_APP="${GALLERY_BACKDROP_APP:-Visual Studio Code}"
USE_BACKDROP=1
DRY_RUN=0
PUBLISH=0
TAG="gallery"

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --dry-run             print the whole plan and exit, touching nothing
  --mode display|window display = the real screen (default); window = the overlay
                        panel alone, composited over a still backdrop
  --only a,b,c          record only these effects
  --skip a,b            skip these on top of the built-in skips
  --backdrop FILE       file to open in the backdrop app (default tools/gallery-assets/Backdrop.java)
  --backdrop-app NAME   app to open it with (default "Visual Studio Code", env GALLERY_BACKDROP_APP)
  --no-backdrop         record over whatever is already on screen
  --width N             output width in px (default 1440)
  --out DIR             working/output directory (default .build/gallery)
  --publish             upload the montage to the '<tag>' GitHub release with gh
  --tag NAME            release tag to publish under (default "gallery")
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --mode) MODE="$2"; shift ;;
    --only) ONLY="$2"; shift ;;
    --skip) EXTRA_SKIP="$2"; shift ;;
    --backdrop) BACKDROP_FILE="$2"; shift ;;
    --backdrop-app) BACKDROP_APP="$2"; shift ;;
    --no-backdrop) USE_BACKDROP=0 ;;
    --width) WIDTH="$2"; shift ;;
    --fps) FPS="$2"; shift ;;
    --out) OUT="$2"; shift ;;
    --publish) PUBLISH=1 ;;
    --tag) TAG="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
die() { printf 'record-gallery: %s\n' "$*" >&2; exit 1; }
api() { curl -fsS --max-time 3 "$BASE$1"; }

# ---------------------------------------------------------------------------
# 🔒 Taking the screen is not something to do silently
#
# Every frame below is a recording of Victor's actual display, and the effects
# draw on top of whatever he is doing. The locks are the contract that says so,
# and `hands-off run` is the form that releases them on exit, on Ctrl-C and on a
# crash. caffeinate is in the same exec because a display that sleeps mid-run
# does not produce black frames — it produces no frames at all, and the run ends
# with 40 empty clips and no error.
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" = 0 ] && [ -z "${GALLERY_LOCKED:-}" ]; then
  HANDS_OFF="${HANDS_OFF:-$HOME/bin/hands-off}"
  [ -x "$HANDS_OFF" ] || die "$HANDS_OFF is missing — it is what puts the 🔒 on screen while this records. Install victor-macos-addons or set HANDS_OFF."
  exec "$HANDS_OFF" run "recording the Victor Effects gallery" -- \
       caffeinate -disu env GALLERY_LOCKED=1 "$0" "$@"
fi

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
for tool in curl ffmpeg ffprobe swiftc; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed (brew install ffmpeg for the first two)"
done
[ "$PUBLISH" = 1 ] && { command -v gh >/dev/null 2>&1 || die "--publish needs the gh CLI"; }

PING="$(api /ping || true)"
case "$PING" in
  *'"app":"victor-effects"'*) ;;
  *) die "nothing answering /ping on $BASE — open \"/Applications/Victor Effects.app\" first" ;;
esac
BUILD_STAMP="$(printf '%s' "$PING" | sed -n 's/.*"effectsVersion":"\([^"]*\)".*/\1/p')"

RECORDER="$REPO/.build/gallery/gallery-recorder"
mkdir -p "$(dirname "$RECORDER")" "$OUT"
# Rebuilt only when the source is newer: a gallery run should not pay 5 s of
# swiftc every time, and should never silently use a stale recorder.
if [ ! -x "$RECORDER" ] || [ "$REPO/tools/gallery-recorder.swift" -nt "$RECORDER" ]; then
  say "building the recorder…"
  swiftc -O -target "$(uname -m)-apple-macos14.0" -framework ScreenCaptureKit \
         -o "$RECORDER" "$REPO/tools/gallery-recorder.swift" 2>&1 | grep -E 'error:'
  [ -x "$RECORDER" ] || die "the recorder did not build"
fi

# `--probe` is also the Screen Recording check: without the grant SCK never
# answers and the recorder says so instead of hanging forever.
PROBE="$("$RECORDER" --probe 2>&1)" || die "$PROBE"
OVERLAY_WID="$(printf '%s\n' "$PROBE" | awk '/layer=2147483/ {print $2}' | cut -d= -f2 | head -1)"
[ -n "$OVERLAY_WID" ] || die "the app's overlay window is not in ScreenCaptureKit's list — is Victor Effects running?"

# ---------------------------------------------------------------------------
# The effect list, parsed from the source that defines it
#
# `EffectsCatalog`/`GET /effects/assets` answers a different question (which
# *sounds* also animate the desktop), so it is the wrong list to build a gallery
# of effects from. The right one is `fireEffect`'s switch, which is exactly what
# `SoundEffectMapDriftTests` parses — including its guard against parser rot: a
# parse that silently comes back empty would produce an empty gallery and no
# error at all.
# ---------------------------------------------------------------------------
ALL_CASES="$(awk '
  /private func fireEffect\(_ name: String\) \{/ { inside = 1; next }
  inside && /^    func stopAll/ { exit }
  inside && /^ *case "/ { print }
' "$REPO/Sources/VictorEffects/EffectsEngine.swift" \
  | sed 's/:.*//' \
  | grep -o '"[^"]*"' | tr -d '"')"
# The `sed 's/:.*//'` is not tidiness: `case "heart": animator.spawnEmoji("❤️")`
# has two string literals on the line, and without cutting at the colon the ❤️
# itself arrives as an effect name and the run tries to GET /effect/❤️.
CASE_COUNT="$(printf '%s\n' "$ALL_CASES" | grep -c . )"
[ "$CASE_COUNT" -gt 30 ] || die "only parsed $CASE_COUNT effect names out of fireEffect — the switch changed shape; fix this parser, do not lower the number"

# Why each name is not in the gallery. Left of the | is the effect, right is the
# reason, printed by --dry-run so a skip is never a mystery.
SKIPS='stop-all|not an effect, it is the off switch
click|audible only, nothing is drawn
whip/crack|a flick of the whip, meaningless without a hand on the mouse
coffee/pop|fires the eventWebhook at the addons app: a real side effect, not a picture'

# Effects that draw in their OWN window rather than on the overlay panel, and so
# are invisible to --mode window. Found by grepping for NSPanel/NSWindow in
# Sources: EdgeFlash, PeekMascot, RedButton, WhipOverlay.
OWN_WINDOW="green-flash claude-peek red-button whip"

# Effects that copy the real screen into themselves (`captureBuiltInDisplay*`)
# to distort it. In --mode window they would smuggle Victor's actual desktop
# INTO the overlay window's own pixels, which is the one thing window mode
# exists to avoid.
SCREEN_SAMPLING="broken-glass earthquake chainsaw heartbeat fbi-knock dark-door beethoven phone-ring"

in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
skip_reason() {
  printf '%s\n' "$SKIPS" | awk -F'|' -v n="$1" '$1 == n { print $2; found = 1 } END { exit !found }'
}

# Routes that are not simply /effect/<name>, and the stop that has to follow.
# Everything else self-terminates (the lifecycle rule in docs/overlay-effects.md).
effect_url() {
  case "$1" in
    alarm)        echo "/alarm/start" ;;
    emoji)        echo "/effect/emoji?e=%E2%9D%A4%EF%B8%8F&count=12&glow=%F0%9F%92%9B" ;;
    progress-bar) echo "/effect/progress-bar/6?rider=%F0%9F%8F%81" ;;
    *)            echo "/effect/$1" ;;
  esac
}
# Effects that outlive their clip on purpose need an explicit exit, and a length
# to record for, since /state will never stop reporting them.
effect_hold() {
  case "$1" in
    alarm)        echo "6|/alarm/stop" ;;
    whip)         echo "5|/effect/whip" ;;       # a toggle: the same route puts it away
    red-button)   echo "7|/effect/red-button/stop" ;;
    coffee)       echo "7|/effect/stop-all" ;;   # the ☕ wait for a cursor that will not come
    elephant)     echo "9|/effect/elephant/stop" ;;
    claude-peek)  echo "5|/effect/claude-peek/stop" ;;
    progress-bar) echo "8|/effect/progress-bar/stop" ;;
    # The emoji spawners put layers straight on the hostLayer instead of going
    # through `trackEffect`, so they never appear in activeEffects and the
    # /state loop would fall through both waits in an instant.
    emoji|heart|confetti|corner-confetti) echo "5|/effect/stop-all" ;;
    *)            echo "" ;;
  esac
}

EFFECTS=""
for name in $ALL_CASES; do
  case "$name" in */stop) continue ;; esac
  EFFECTS="$EFFECTS $name"
done
# Three effects are missing from `fireEffect`'s switch on purpose, because they
# take an argument and so have `Route` cases of their own in `EffectsRouter`
# (`docs/http-api.md`). A gallery parsed only from the switch would silently
# leave out the siren, the emoji fountain and the progress bar — so they are
# named here, next to the parser that cannot see them.
#   alarm        — EffectsCatalog.sirenEffectName, a toggle via /alarm/*
#   emoji        — /effect/emoji?e=…&count=…  (count is clamped 1…50)
#   progress-bar — /effect/progress-bar/<seconds>?rider=…
EFFECTS="$EFFECTS alarm emoji progress-bar"

PLAN=""
SKIPPED=""
for name in $EFFECTS; do
  if [ -n "$ONLY" ] && ! printf '%s' ",$ONLY," | grep -q ",$name,"; then continue; fi
  if reason="$(skip_reason "$name")"; then SKIPPED="$SKIPPED$name — $reason"$'\n'; continue; fi
  if [ -n "$EXTRA_SKIP" ] && printf '%s' ",$EXTRA_SKIP," | grep -q ",$name,"; then
    SKIPPED="$SKIPPED$name — asked for with --skip"$'\n'; continue
  fi
  if [ "$MODE" = "window" ]; then
    if in_list "$name" "$OWN_WINDOW"; then
      SKIPPED="$SKIPPED$name — draws in its own window, invisible to --mode window"$'\n'; continue
    fi
    if in_list "$name" "$SCREEN_SAMPLING"; then
      SKIPPED="$SKIPPED$name — copies the real screen into itself, which --mode window exists to avoid"$'\n'; continue
    fi
  fi
  PLAN="$PLAN $name"
done
PLAN_COUNT="$(printf '%s\n' $PLAN | grep -c .)"

# ---------------------------------------------------------------------------
# Dry run: the whole plan, no screen touched
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" = 1 ]; then
  say "app          : $BASE (build $BUILD_STAMP)"
  say "mode         : $MODE"
  say "overlay win  : $OVERLAY_WID"
  say "$(printf '%s\n' "$PROBE" | sed -n 's/^display /displays     : /p')"
  say "parsed       : $CASE_COUNT case labels from fireEffect"
  say "recording    : $PLAN_COUNT effects"
  say "backdrop     : $([ "$USE_BACKDROP" = 1 ] && echo "$BACKDROP_FILE in $BACKDROP_APP" || echo "whatever is on screen")"
  say "output       : $OUT/effects-gallery.mp4  (${WIDTH}px wide, ${FPS} fps)"
  say "publish      : $([ "$PUBLISH" = 1 ] && echo "gh release '$TAG'" || echo "no (pass --publish)")"
  say "locks        : hands-off run … -- caffeinate -disu $0 $*"
  say ""
  say "would record, in order:"
  for name in $PLAN; do
    hold="$(effect_hold "$name")"
    if [ -n "$hold" ]; then
      len="${hold%%|*}"; stop="${hold#*|}"
      printf '  %-16s GET %-52s hold %ss then GET %s\n' "$name" "$(effect_url "$name")" "$len" "$stop"
    else
      printf '  %-16s GET %-52s until /state drops it (%s–%ss)\n' "$name" "$(effect_url "$name")" "$MIN_CLIP" "$MAX_CLIP"
    fi
  done
  say ""
  say "would skip:"
  printf '%s' "$SKIPPED" | sed 's/^/  /'
  exit 0
fi

# ---------------------------------------------------------------------------
# Backdrop
# ---------------------------------------------------------------------------
BACKDROP_PNG="$OUT/backdrop.png"
if [ "$USE_BACKDROP" = 1 ]; then
  [ -f "$BACKDROP_FILE" ] || die "no backdrop file at $BACKDROP_FILE"
  say "opening the backdrop in $BACKDROP_APP…"
  open -a "$BACKDROP_APP" "$BACKDROP_FILE" 2>/dev/null \
    || say "  (could not open $BACKDROP_APP — recording over whatever is on screen)"
  sleep 3
fi
if [ "$MODE" = "window" ]; then
  # Window mode composites over a STILL of the screen, taken once, here. A still
  # is the one capture `screencapture` still does from a script.
  screencapture -x -o -D1 "$BACKDROP_PNG" || die "could not take the backdrop still"
fi

api /effect/stop-all >/dev/null 2>&1

# ---------------------------------------------------------------------------
# Record
# ---------------------------------------------------------------------------
# Only the activeEffects array, never the whole /state body: that body also
# carries the live config, and a name that happened to match a config key would
# make an effect look like it never ends.
state_has() {
  api /state 2>/dev/null \
    | sed -n 's/.*"activeEffects":\[\([^]]*\)\].*/\1/p' \
    | grep -q "\"$1\""
}

CLIPS=""
FAILED=""
i=0
for name in $PLAN; do
  i=$((i + 1))
  slug="$(printf '%s' "$name" | tr '/' '-')"
  raw="$OUT/raw-$slug.mp4"
  clip="$OUT/clip-$(printf '%02d' "$i")-$slug.mp4"
  fifo="$OUT/.stop.$$"

  api /effect/stop-all >/dev/null 2>&1
  sleep "$SETTLE"

  rm -f "$fifo" "$raw"; mkfifo "$fifo"
  if [ "$MODE" = "window" ]; then
    "$RECORDER" --out "$raw" --window "$OVERLAY_WID" --backdrop "$BACKDROP_PNG" \
                --width "$WIDTH" --fps "$FPS" --seconds "$((MAX_CLIP + 6))" < "$fifo" &
  else
    "$RECORDER" --out "$raw" --display builtin \
                --width "$WIDTH" --fps "$FPS" --seconds "$((MAX_CLIP + 6))" < "$fifo" &
  fi
  rec=$!
  # `3<>` rather than `3>`: opening a fifo write-only blocks until a reader
  # shows up, so a recorder that died on startup would hang the whole run here
  # instead of failing the clip.
  exec 3<> "$fifo"
  sleep "$WARMUP"

  api "$(effect_url "$name")" >/dev/null 2>&1
  hold="$(effect_hold "$name")"
  started=$(date +%s)
  if [ -n "$hold" ]; then
    sleep "${hold%%|*}"
    api "${hold#*|}" >/dev/null 2>&1
    sleep 0.6
  else
    # Wait for /state to pick it up (some effects start after a bluetooth
    # compensation delay), then for it to let go. The floor is there because
    # several effects are shorter than a glance; the cap is there because an
    # effect that never clears must not stall the whole run.
    waited=0
    while [ "$waited" -lt 20 ] && ! state_has "$name"; do sleep 0.25; waited=$((waited + 1)); done
    while [ $(( $(date +%s) - started )) -lt "$MAX_CLIP" ] && state_has "$name"; do sleep 0.25; done
    elapsed=$(( $(date +%s) - started ))
    # Effects with no entry in activeEffects at all (the emoji spawners) fall
    # straight through both loops — the floor is what gives them a clip.
    rest=$(printf '%s - %s\n' "$MIN_CLIP" "$elapsed" | bc)
    case "$rest" in -*|0) ;; *) sleep "$rest" ;; esac
  fi

  printf 'stop\n' >&3; exec 3>&-
  wait "$rec"; rc=$?
  rm -f "$fifo"
  api /effect/stop-all >/dev/null 2>&1

  if [ "$rc" != 0 ] || [ ! -s "$raw" ]; then
    say "  ✗ $name — recorder exited $rc (no frames?)"
    FAILED="$FAILED $name"
    continue
  fi

  dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$raw")"
  label="$OUT/label-$slug.png"
  "$RECORDER" --label "$name" --sublabel "GET $(effect_url "$name")" --width "$WIDTH" --out "$label"
  # scale → even dimensions → label at the bottom left → a short fade in/out so
  # the montage does not cut hard between 40 unrelated effects.
  ffmpeg -v error -y -i "$raw" -i "$label" -filter_complex \
    "[0:v]fps=$FPS,scale=$WIDTH:-2,setsar=1[v];[1:v]scale=$WIDTH:-1[l];[v][l]overlay=0:H-h[o];[o]fade=t=in:st=0:d=0.25,fade=t=out:st=$(printf '%s - 0.35\n' "$dur" | bc):d=0.35[f]" \
    -map "[f]" -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p "$clip" \
    || { say "  ✗ $name — ffmpeg could not cut the clip"; FAILED="$FAILED $name"; continue; }
  rm -f "$raw" "$label"
  CLIPS="$CLIPS $clip"
  printf '  ✓ %-16s %ss\n' "$name" "$(printf '%.1f' "$dur")"
done

[ -n "$CLIPS" ] || die "not one clip came out — nothing to assemble"

# ---------------------------------------------------------------------------
# Assemble
# ---------------------------------------------------------------------------
say "assembling…"
LIST="$OUT/clips.txt"
: > "$LIST"
for clip in $CLIPS; do printf "file '%s'\n" "$clip" >> "$LIST"; done

GALLERY="$OUT/effects-gallery.mp4"
ffmpeg -v error -y -f concat -safe 0 -i "$LIST" -c:v libx264 -preset slow -crf 24 \
       -pix_fmt yuv420p -movflags +faststart "$GALLERY" || die "the montage did not assemble"

# A poster frame for the README/release page, taken from the middle of the film.
POSTER="$OUT/effects-gallery.jpg"
MID="$(printf '%s / 2\n' "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$GALLERY")" | bc)"
ffmpeg -v error -y -ss "$MID" -i "$GALLERY" -frames:v 1 -q:v 3 "$POSTER" >/dev/null 2>&1

say ""
say "gallery : $GALLERY ($(du -h "$GALLERY" | cut -f1))"
say "poster  : $POSTER"
[ -n "$FAILED" ] && say "failed  :$FAILED"

# ---------------------------------------------------------------------------
# Publish
#
# Deliberately NOT committed. This repo is public and a montage of 40 effects is
# tens of megabytes of binary that git would keep forever, in a checkout whose
# entire source tree is under a megabyte. A GitHub release asset is the same
# link for everyone, replaceable in place, and weighs nothing in the clone.
# ---------------------------------------------------------------------------
if [ "$PUBLISH" = 1 ]; then
  gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
  if ! gh release view "$TAG" >/dev/null 2>&1; then
    gh release create "$TAG" --title "Effects gallery" \
      --notes "Every overlay effect, recorded over a real editor window. Regenerated by \`tools/record-gallery.sh\`." \
      || die "could not create the '$TAG' release"
  fi
  gh release upload "$TAG" "$GALLERY" "$POSTER" --clobber || die "could not upload the gallery"
  say "published: $(gh release view "$TAG" --json url -q .url)"
  say "permalink: https://github.com/victorrentea/victor-effects/releases/latest/download/effects-gallery.mp4"
fi
