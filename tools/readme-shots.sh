#!/bin/bash
# Renders the right-⌘ panel's two pages — soundboard and videos — to PNG for
# the README. CI runs it on every push (.github/workflows/readme-shots.yml);
# locally it is the same command, so a picture that looks wrong can be
# reproduced without a runner.
#
#   tools/readme-shots.sh <soundsDir> [outDir]
#
# <soundsDir> holds tiles.json and tiles/ (the tablet repo's app/src/main/assets).
# The video list is the committed snapshot tools/readme-shots/videos.json —
# the live one lives on the addons app of one Mac, which no runner can reach;
# refresh it with tools/readme-shots/snapshot-videos.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

SOUNDS_DIR="$(cd "${1:?usage: $0 <soundsDir> [outDir]}" && pwd)"
OUT_DIR="${2:-.build/readme-shots}"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

README_SHOTS_OUT="$OUT_DIR" \
README_SHOTS_SOUNDS_DIR="$SOUNDS_DIR" \
README_SHOTS_VIDEOS="$PWD/tools/readme-shots/videos.json" \
  swift test --filter ReadmeShotsTests

for f in soundboard.png videos.png; do
  [ -s "$OUT_DIR/$f" ] || { echo "❌ $OUT_DIR/$f was not written" >&2; exit 1; }
done
ls -l "$OUT_DIR"
