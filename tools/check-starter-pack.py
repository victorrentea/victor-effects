#!/usr/bin/env python3
"""Every file in starter-pack/ is credited, under a licence that allows
redistribution — or the release stops.

starter-pack/credits.json is the ledger: [{file, license, author, source, …}].
Run by tools/release.sh; also safe to run by hand. Exit 1 on any problem.
"""
import json, os, sys

ALLOWED = {"CC0-1.0", "PD", "CC-BY-3.0", "CC-BY-4.0", "Attribution", "Apache-2.0", "own-CC0"}
META = {"tiles.json", "credits.json", "CREDITS.md", "README.md", "sound-timing.json"}

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "starter-pack")
credits = json.load(open(os.path.join(root, "credits.json")))
by_file = {c["file"]: c for c in credits}
problems = []
for c in credits:
    if c.get("license") not in ALLOWED:
        problems.append(f"{c['file']}: licence {c.get('license')!r} is not one of {sorted(ALLOWED)}")
    if c["license"] not in ("own-CC0",) and not c.get("source"):
        problems.append(f"{c['file']}: no source URL")
    if c["license"].startswith("CC-BY") or c["license"] in ("Attribution", "Apache-2.0"):
        if not c.get("attribution"):
            problems.append(f"{c['file']}: {c['license']} without an attribution string")
    if not os.path.exists(os.path.join(root, c["file"])):
        problems.append(f"{c['file']}: credited but not in starter-pack/")
for dirpath, _, files in os.walk(root):
    for f in files:
        rel = os.path.relpath(os.path.join(dirpath, f), root)
        if rel in META or f.startswith("."):
            continue
        if rel not in by_file:
            problems.append(f"{rel}: in starter-pack/ but not in credits.json")
tiles = json.load(open(os.path.join(root, "tiles.json")))["tiles"]
for t in tiles:
    for k in ("asset", "image"):
        if not os.path.exists(os.path.join(root, t[k])):
            problems.append(f"tiles.json #{t['n']}: {t[k]} missing")
if problems:
    print("❌ starter-pack:\n   " + "\n   ".join(problems))
    sys.exit(1)
print(f"starter-pack: OK — {len(credits)} files, all credited ({len(tiles)} tiles)")
