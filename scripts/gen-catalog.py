#!/usr/bin/env python3
"""Generate the bundled catalog.json that ships inside the app.

Scans Sources/XNoise/Resources/sounds/ for MP3 files and produces a
catalog document with `kind: "bundled"` entries. The app reads this
file from its Bundle at launch — no HTTP server, no R2, no downloads.

Run from project root:
    python3 scripts/gen-catalog.py > Sources/XNoise/Resources/catalog.json
"""
import argparse
import json
import os
import sys

# Momentum-style taxonomy — track id (matches filename stem) per category.
CATEGORIES = [
    ("noise", "Noise", [
        "white_noise", "pink_noise", "brown_noise", "green_noise", "fluorescent_hum",
    ]),
    ("soundscapes", "Soundscapes", [
        "rain", "rain_on_surface", "loud_rain", "thunder", "wind",
        "ocean", "ocean_waves", "ocean_birds", "ocean_boat",
        "ocean_bubbles", "ocean_splash", "seagulls",
        "birds", "crickets", "insects", "fire", "stream",
    ]),
    ("ambient", "Ambient", [
        "cafe", "coffee_maker", "mechanical_keyboard", "copier",
        "airplane_cabin", "air_conditioner", "co_workers", "chimes", "train_tracks",
    ]),
    ("binaural", "Binaural", [
        "binaural_music",
    ]),
    ("speech-blocker", "Speech Blocker", [
        "speech_blocker",
    ]),
]


def pretty_name(track_id: str) -> str:
    return track_id.replace("_", " ").title()


def build(sounds_dir: str) -> dict:
    categories = []
    seen = set()

    for cat_id, cat_name, track_ids in CATEGORIES:
        tracks = []
        for tid in track_ids:
            fname = f"{tid}.mp3"
            fpath = os.path.join(sounds_dir, fname)
            if not os.path.isfile(fpath):
                print(f"warn: missing {fpath}", file=sys.stderr)
                continue
            seen.add(fname)
            tracks.append({
                "id": tid,
                "name": pretty_name(tid),
                "kind": "bundled",
                "filename": fname,
            })
        if tracks:
            categories.append({"id": cat_id, "name": cat_name, "tracks": tracks})

    on_disk = {f for f in os.listdir(sounds_dir) if f.endswith(".mp3")}
    unplaced = on_disk - seen
    if unplaced:
        print(f"warn: unplaced files in sounds/: {sorted(unplaced)}", file=sys.stderr)

    return {"schemaVersion": 1, "categories": categories}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sounds-dir", default="Sources/XNoise/Resources/sounds")
    args = ap.parse_args()

    doc = build(args.sounds_dir)
    json.dump(doc, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
