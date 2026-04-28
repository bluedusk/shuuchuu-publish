#!/usr/bin/env bash
# Fetch ~100 high-view ambience clips from YouTube (5:00-8:00 each, raw Opus).
# Output: my_sounds/<id>_<title>_5-8.webm
set -uo pipefail

DEST="/Users/dan/playground/x-noise/my_sounds"
ARCHIVE="$DEST/.archive"
CANDIDATES="$DEST/.candidates.tsv"
CURATED="$DEST/.curated.tsv"
LOG="$DEST/.download.log"

mkdir -p "$DEST"
: > "$CANDIDATES"
: > "$LOG"

QUERIES=(
  # Rain
  "heavy rain ambience no music"
  "rain on tent no music"
  "rain on window relaxing no music"
  "rain on roof no music"
  "rainstorm thunder no music"
  "rain on leaves forest no music"
  "rain on car no music"
  # Water
  "ocean waves no music"
  "ocean storm no music"
  "river stream water no music"
  "waterfall sound no music"
  "underwater sound no music"
  # Forest / nature
  "forest ambience no music"
  "forest birds chirping no music"
  "jungle rainforest no music"
  "summer night nature sounds no music"
  # Wind
  "wind howling no music"
  "blizzard snow storm no music"
  # Animals
  "crickets at night no music"
  "frogs pond ambience"
  "birds chirping forest morning"
  "cat purring asmr"
  # Fire
  "campfire crackling no music"
  "fireplace fire no music"
  # Noise
  "white noise fan"
  "brown noise"
  "pink noise"
  "fan white noise"
  # Vehicle / urban
  "airplane cabin sound no music"
  "train interior sound no music"
  "subway ambience no music"
  "city street ambience no music"
  "highway traffic no music"
  "boat sound no music"
  "spaceship ambience no music"
  # Indoor / mechanical
  "coffee shop ambience no music"
  "library ambience no music"
  "office ambience no music"
  "washing machine sound"
  "dryer sound asmr"
  "air conditioner sound"
  "refrigerator hum"
  "clock ticking no music"
  # Misc
  "snowfall forest ambience"
  "campsite night sound"
  "ASMR rain ambience"
  "thunderstorm window view"
)

echo "[$(date)] Starting discovery for ${#QUERIES[@]} queries" | tee -a "$LOG"

for q in "${QUERIES[@]}"; do
  echo "[$(date)] Searching: $q" >> "$LOG"
  yt-dlp --quiet --no-warnings --skip-download \
    --match-filter "view_count > 200000 & duration > 600" \
    --print "%(id)s	%(view_count)s	%(duration)s	%(title)s" \
    "ytsearch10:$q" 2>> "$LOG" >> "$CANDIDATES" || true
done

echo "[$(date)] Discovery done. Total candidates: $(wc -l < "$CANDIDATES")" | tee -a "$LOG"

# Dedup by video id, sort by views desc, take top 100
sort -u -k1,1 -t'	' "$CANDIDATES" | sort -k2,2 -nr -t'	' | head -100 > "$CURATED"
echo "[$(date)] Curated $(wc -l < "$CURATED") videos for download" | tee -a "$LOG"

# Phase 3: parallel download (3 workers)
echo "[$(date)] Starting parallel downloads" | tee -a "$LOG"
awk -F'	' '{print $1}' "$CURATED" | \
  xargs -n 1 -P 3 -I {} bash -c '
    id="$1"; dest="'"$DEST"'"; archive="'"$ARCHIVE"'"; log="'"$LOG"'"
    if yt-dlp --quiet --no-warnings -f bestaudio --download-sections "*5:00-8:00" \
        --force-keyframes-at-cuts \
        --download-archive "$archive" \
        --restrict-filenames \
        -o "$dest/%(id)s_%(title).60s_5-8.%(ext)s" \
        "https://www.youtube.com/watch?v=$id" >>"$log" 2>&1; then
      echo "[$(date)] OK $id" >> "$log"
    else
      echo "[$(date)] FAIL $id" >> "$log"
    fi
  ' _ {}

count=$(ls "$DEST"/*.webm 2>/dev/null | wc -l | tr -d " ")
echo "[$(date)] Done. Total .webm files in dir: $count" | tee -a "$LOG"
