#!/usr/bin/env python3
"""Generate the bundled catalog.json that ships inside the app.

Scans Sources/Shuuchuu/Resources/sounds/ for MP3 files and produces a
catalog document with `kind: "bundled"` entries. The app reads this
file from its Bundle at launch — no HTTP server, no R2, no downloads.

Run from project root:
    python3 scripts/gen-catalog.py > Sources/Shuuchuu/Resources/catalog.json
"""
import argparse
import json
import os
import sys
from typing import Optional

# Moodist-style taxonomy — each track in exactly one category.
CATEGORIES = [
    ("rain", "Rain", [
        "rain", "rain_on_surface", "loud_rain", "thunder",
    ]),
    ("nature", "Nature", [
        "wind", "fire", "stream",
        "ocean", "ocean_waves", "ocean_boat", "ocean_bubbles", "ocean_splash",
    ]),
    ("animals", "Animals", [
        "birds", "ocean_birds", "seagulls", "crickets", "insects",
    ]),
    ("places", "Places", [
        "cafe", "coffee_maker", "co_workers",
    ]),
    ("transport", "Transport", [
        "airplane_cabin", "train_tracks",
    ]),
    ("things", "Things", [
        "mechanical_keyboard", "copier", "chimes", "air_conditioner",
    ]),
    ("noise", "Noise", [
        "white_noise", "pink_noise", "brown_noise", "green_noise", "fluorescent_hum",
    ]),
    ("focus", "Focus", [
        "binaural_music", "speech_blocker",
    ]),
]


def pretty_name(track_id: str) -> str:
    return track_id.replace("_", " ").title()


AUDIO_EXTS = (".mp3", ".wav", ".m4a", ".caf", ".aif", ".aiff", ".flac")


def find_audio_file(sounds_dir: str, track_id: str) -> Optional[str]:
    """Return the filename for a track id, probing supported audio extensions in
    preference order (mp3 first since most of the catalog is MP3, then lossless)."""
    for ext in AUDIO_EXTS:
        fname = f"{track_id}{ext}"
        if os.path.isfile(os.path.join(sounds_dir, fname)):
            return fname
    return None


def build(sounds_dir: str) -> dict:
    categories = []
    seen = set()

    for cat_id, cat_name, track_ids in CATEGORIES:
        tracks = []
        for tid in track_ids:
            fname = find_audio_file(sounds_dir, tid)
            if fname is None:
                print(f"warn: missing audio for {tid} (any of {AUDIO_EXTS})", file=sys.stderr)
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

    on_disk = {f for f in os.listdir(sounds_dir) if f.lower().endswith(AUDIO_EXTS)}
    unplaced = on_disk - seen
    if unplaced:
        print(f"warn: unplaced files in sounds/: {sorted(unplaced)}", file=sys.stderr)

    return {"schemaVersion": 1, "categories": categories}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sounds-dir", default="Sources/Shuuchuu/Resources/sounds")
    args = ap.parse_args()

    doc = build(args.sounds_dir)
    json.dump(doc, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
