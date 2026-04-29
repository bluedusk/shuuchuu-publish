#!/usr/bin/env python3
"""Generate the bundled scenes.json that ships inside the app.

Scans Sources/Shuuchuu/Resources/shaders/ for `<id>.metal` files (excluding
`_`-prefixed shared files) and pairs each one with `<id>.jpg`. Files without a
matching thumbnail are skipped with a warning.

Run from project root:
    python3 scripts/gen-scenes.py > Sources/Shuuchuu/Resources/scenes.json
"""
import json
import os
import sys

SCENES_DIR = "Sources/Shuuchuu/Resources/shaders"


def humanize(stem: str) -> str:
    return stem.replace("-", " ").replace("_", " ").title()


def main() -> int:
    if not os.path.isdir(SCENES_DIR):
        print("[]")
        return 0
    entries = []
    for name in sorted(os.listdir(SCENES_DIR)):
        if not name.endswith(".metal") or name.startswith("_"):
            continue
        stem = name[: -len(".metal")]
        thumb = f"{stem}.jpg"
        if not os.path.exists(os.path.join(SCENES_DIR, thumb)):
            print(f"warning: missing thumbnail {thumb} for {name}",
                  file=sys.stderr)
            continue
        entries.append({
            "id": stem,
            "title": humanize(stem),
            "thumbnail": thumb,
            "kind": "shader",
        })
    json.dump(entries, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
