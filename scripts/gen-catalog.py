#!/usr/bin/env python3
"""Generate catalog.json that ships inside the app.

Scans Sources/Shuuchuu/Resources/sounds/ for audio files and produces a
catalog document. Two modes:

- `streamed` (default): each entry is `kind: "streamed"` with
  url=<base-url>/<prefix>/<id>.<ext>, sha256 (for integrity), and bytes.
  The audio files are NOT bundled — they live in R2 and stream on demand.
- `bundled`: each entry is `kind: "bundled"` with `filename`. Used only
  if you want to ship the audio inside the app (legacy / offline build).

Run from project root:
    python3 scripts/gen-catalog.py > Sources/Shuuchuu/Resources/catalog.json
    python3 scripts/gen-catalog.py --prefix loops > Sources/Shuuchuu/Resources/catalog.json
    python3 scripts/gen-catalog.py --mode bundled > Sources/Shuuchuu/Resources/catalog.json
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from typing import Optional

# Moodist-style taxonomy — each track in exactly one category.
CATEGORIES = [
    ("rain", "Rain", [
        "rain", "rain_on_surface", "loud_rain", "thunder",
    ]),
    ("nature", "Nature", [
        "wind", "fire", "campfire_river", "stream",
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


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def kbps_of(path: str) -> Optional[int]:
    """Return the audio bitrate in kbps, rounded to the nearest kilobit, or
    None if ffprobe isn't available or the file has no audio stream."""
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "a:0",
             "-show_entries", "stream=bit_rate", "-of", "csv=p=0", path],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    if not out or out == "N/A":
        return None
    try:
        return round(int(out) / 1000)
    except ValueError:
        return None


def build(sounds_dir: str, mode: str, base_url: str, prefix: str) -> dict:
    categories = []
    seen = set()
    prefix = prefix.strip("/")

    for cat_id, cat_name, track_ids in CATEGORIES:
        tracks = []
        for tid in track_ids:
            fname = find_audio_file(sounds_dir, tid)
            if fname is None:
                print(f"warn: missing audio for {tid} (any of {AUDIO_EXTS})", file=sys.stderr)
                continue
            seen.add(fname)
            path = os.path.join(sounds_dir, fname)
            entry: dict = {"id": tid, "name": pretty_name(tid)}
            if mode == "bundled":
                entry["kind"] = "bundled"
                entry["filename"] = fname
            else:
                ext = os.path.splitext(fname)[1].lstrip(".").lower()
                digest = sha256_of(path)
                kbps = kbps_of(path)
                stem = f"{tid}_{kbps}kbps" if kbps else tid
                key = f"{prefix}/{stem}.{ext}" if prefix else f"{stem}.{ext}"
                entry["kind"] = "streamed"
                entry["url"] = f"{base_url.rstrip('/')}/{key}"
                entry["sha256"] = digest
                entry["bytes"] = os.path.getsize(path)
            tracks.append(entry)
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
    ap.add_argument("--mode", choices=["streamed", "bundled"], default="streamed")
    ap.add_argument("--base-url", default="https://music.secure-app.download")
    ap.add_argument("--prefix", default="loops",
                    help="key prefix in the bucket (e.g. 'loops' -> loops/<id>.mp3). Empty for flat.")
    args = ap.parse_args()

    doc = build(args.sounds_dir, args.mode, args.base_url, args.prefix)
    json.dump(doc, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
