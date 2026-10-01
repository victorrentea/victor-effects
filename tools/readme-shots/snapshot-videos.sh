#!/bin/bash
# Snapshots the addons app's GET /videos (titles + inline thumbnails) into
# videos.json next to this script, for the README's video page. Run it after
# adding a training video, then commit — the push re-renders the README.
set -euo pipefail
cd "$(dirname "$0")"
BASE="${VICTOR_EFFECTS_ADDONS_URL:-http://127.0.0.1:55123}"
curl -sf -m 5 "$BASE/videos" | python3 -c '
import json, sys
videos = json.load(sys.stdin)["videos"]
keep = [{k: v[k] for k in ("id", "title", "startSeconds", "thumb") if k in v} for v in videos]
# One video per line, so a diff names the clip that changed.
print("{\"videos\": [\n" + ",\n".join(json.dumps(v, ensure_ascii=False) for v in keep) + "\n]}")
' > videos.json.tmp
mv videos.json.tmp videos.json
echo "✅ $(grep -c '"id"' videos.json) videos → $(pwd)/videos.json"
