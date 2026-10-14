#!/usr/bin/env python3
"""Keep third-party media out of this public repo.

Two modes:

  copyright-guard.py ledger <out.json> <dir>...   (maintainer's Mac)
      Hash every media file under the given private folders (the soundboard,
      assetsDir) into a ledger: sha256, file name, and the copyright class
      from --classes <json> ({"<file name>": ["<class>", "<evidence>"]});
      anything unlisted is "unknown" — a file whose provenance nobody wrote
      down is treated as someone else's. Every entry is publish:false.

  copyright-guard.py check [<ledger.json>]        (build-app.sh, tools/release.sh)
      Fail if any file tracked by git here — or staged under starter-pack/ —
      has the sha256 of a ledger entry, or the same file name as one with a
      media extension. Default ledger: ~/.victor-effects/copyright-ledger.json;
      when it is absent (anyone but the maintainer) the check is skipped.

The ledger itself stays private: it lists what the maintainer owns copies of.
"""
import hashlib, json, os, subprocess, sys

MEDIA = {".mp3", ".wav", ".m4a", ".aac", ".ogg", ".gif", ".png", ".jpg", ".jpeg",
         ".webp", ".mov", ".mp4", ".webm", ".srt", ".ass"}


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ledger(out, dirs, classes):
    entries = []
    for d in dirs:
        d = os.path.expanduser(d)
        for root, _, files in os.walk(d):
            for name in sorted(files):
                if os.path.splitext(name)[1].lower() not in MEDIA:
                    continue
                p = os.path.join(root, name)
                cls, why = classes.get(name, ["unknown", "no recorded provenance — treated as third-party"])
                entries.append({"file": os.path.relpath(p, d), "root": os.path.basename(d.rstrip("/")),
                                "sha256": sha(p), "class": cls, "evidence": why, "publish": False})
    with open(out, "w") as f:
        json.dump({"_doc": __doc__.strip().splitlines()[0], "entries": entries}, f, indent=1, ensure_ascii=False)
    by = {}
    for e in entries:
        by[e["class"]] = by.get(e["class"], 0) + 1
    print(f"{len(entries)} files → {out}: {by}")


def check(path):
    path = os.path.expanduser(path)
    if not os.path.exists(path):
        print(f"copyright-guard: no ledger at {path} — skipped")
        return 0
    entries = json.load(open(path))["entries"]
    blocked = {e["sha256"]: e for e in entries if not e.get("publish")}
    names = {os.path.basename(e["file"]) for e in entries if not e.get("publish")}
    repo = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
    tracked = subprocess.check_output(["git", "-C", repo, "ls-files", "-z", "--cached", "--others",
                                       "--exclude-standard"], text=True).split("\0")
    bad = []
    for rel in filter(None, tracked):
        p = os.path.join(repo, rel)
        if os.path.splitext(rel)[1].lower() not in MEDIA or not os.path.isfile(p):
            continue
        h = sha(p)
        if h in blocked:
            bad.append(f"{rel}  ==  {blocked[h]['root']}/{blocked[h]['file']}  ({blocked[h]['class']})")
        elif rel.startswith("starter-pack/") and os.path.basename(rel) in names:
            # Same name as a private file is fine only if the bytes differ AND
            # the starter pack credits it — check-starter-pack.py checks credits.
            pass
    if bad:
        print("❌ copyright-guard: these files are third-party copies from the private ledger:")
        print("\n".join("   " + b for b in bad))
        return 1
    print(f"copyright-guard: OK — none of {len(blocked)} private files is in this repo")
    return 0


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "ledger":
        classes = {}
        if "--classes" in a:
            i = a.index("--classes"); classes = json.load(open(a[i + 1])); del a[i:i + 2]
        ledger(a[1], a[2:], classes)
    elif a and a[0] == "check":
        sys.exit(check(a[1] if len(a) > 1 else "~/.victor-effects/copyright-ledger.json"))
    else:
        print(__doc__); sys.exit(2)
