#!/usr/bin/env python3
"""Keep the karaoke tuner (victorrentea.ro/karaoke) and this Mac in step.

    python3 tools/karaoke-sync.py            one round
    python3 tools/karaoke-sync.py install    run it every 2 minutes (LaunchAgent)

A round does two things, each on its own, so an app that is down or a net that
is gone costs only that half until the next round:

1. **Up: what the app ships with.** `GET /sounds/captions/base` plus the clips of
   `soundsDir` go to the site, only when one of them moved. The clips are
   copyrighted: they stay out of the public repo and behind the site's password.
2. **Down: what was tuned.** The edits land in `~/.victor-effects/caption-edits.json`,
   which the app re-reads on the next press (`CaptionEdits`). No build, no restart.

Needs `~/.victor-effects/karaoke-site.json` ({"url": …, "token": …}), which
`tools/karaoke/setup.py` in the victorrentea.ro repo writes. Standard library
only: the LaunchAgent runs it on the system Python.
"""
import hashlib, json, os, plistlib, subprocess, sys, tempfile, urllib.error, urllib.request

HOME = os.path.expanduser("~/.victor-effects")
SITE = os.path.join(HOME, "karaoke-site.json")
EDITS = os.path.join(HOME, "caption-edits.json")
PUBLISHED = os.path.join(HOME, "karaoke-published.txt")
APP = os.environ.get("EFFECTS_URL", "http://127.0.0.1:55124")
LABEL = "ro.victorrentea.karaoke-sync"


def log(msg):
    print(msg, flush=True)


class Site:
    def __init__(self, conf):
        self.url, self.token = conf["url"].rstrip("/"), conf["token"]

    def call(self, action, data=None, query="", content_type="application/json"):
        req = urllib.request.Request(f"{self.url}/api.php?a={action}{query}", data=data, headers={
            "X-Sync-Token": self.token, "User-Agent": "karaoke-sync", "Content-Type": content_type})
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)


def sounds_dir():
    conf = json.load(open(os.path.join(HOME, "config.json")))
    return os.path.expanduser(conf.get("soundsDir", "~/.victor-effects/sounds"))


def sha1(path):
    return hashlib.sha1(open(path, "rb").read()).hexdigest()


def catalog(base, folder):
    """What the tuner starts from: only clips that exist, words as onsets into the clip."""
    assets = {}
    for asset, item in base.items():
        path = os.path.join(folder, asset)
        if not os.path.isfile(path) or not item["cues"]:
            continue
        assets[asset] = {
            "durationSeconds": item["durationSeconds"],
            "sha": sha1(path),
            "cues": [{"at": c["start"], "text": c["text"], "words": c.get("words", [])} for c in item["cues"]],
        }
    return assets


def publish(site):
    try:
        with urllib.request.urlopen(f"{APP}/sounds/captions/base", timeout=10) as r:
            body = r.read()
    except OSError as e:
        log(f"app not reachable, nothing published: {e}")
        return
    folder = sounds_dir()
    assets = catalog(json.loads(body), folder)
    key = hashlib.sha1(json.dumps(assets, sort_keys=True).encode()).hexdigest()
    if os.path.exists(PUBLISHED) and open(PUBLISHED).read().strip() == key:
        return
    have = site.call("sync-have")["have"]
    for asset, item in assets.items():
        if have.get(asset) != item["sha"]:
            data = open(os.path.join(folder, asset), "rb").read()
            site.call("sync-audio", data, f"&f={asset}", "application/octet-stream")
            log(f"uploaded {asset} ({len(data)} bytes)")
    site.call("sync-catalog", json.dumps({"assets": assets}).encode())
    with open(PUBLISHED, "w") as f:
        f.write(key)
    log(f"published {len(assets)} clips")


def pull(site):
    edits = site.call("sync-edits")["edits"]
    body = json.dumps(edits, ensure_ascii=False, sort_keys=True, indent=1)
    if os.path.exists(EDITS) and open(EDITS, encoding="utf-8").read() == body:
        return
    # Atomic: the app re-reads this on a press, and half a file means no edits.
    fd, tmp = tempfile.mkstemp(dir=HOME, prefix=".caption-edits")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(body)
    os.replace(tmp, EDITS)
    log(f"edits: {len(edits)} clip(s)")


def install():
    path = os.path.expanduser(f"~/Library/LaunchAgents/{LABEL}.plist")
    with open(path, "wb") as f:
        plistlib.dump({
            "Label": LABEL,
            "ProgramArguments": ["/usr/bin/python3", os.path.abspath(__file__)],
            "StartInterval": 120,
            "RunAtLoad": True,
            "StandardOutPath": "/tmp/karaoke-sync.log",
            "StandardErrorPath": "/tmp/karaoke-sync.log",
        }, f)
    domain = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", f"{domain}/{LABEL}"], capture_output=True)
    subprocess.run(["launchctl", "bootstrap", domain, path], check=True)
    log(f"installed {path}")


def main():
    if sys.argv[1:] == ["install"]:
        return install()
    site = Site(json.load(open(SITE)))
    for step in (publish, pull):
        try:
            step(site)
        except (OSError, urllib.error.URLError, ValueError) as e:
            log(f"{step.__name__}: {e}")


if __name__ == "__main__":
    main()
