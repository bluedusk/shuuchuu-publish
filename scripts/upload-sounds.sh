#!/usr/bin/env bash
# Upload Resources/sounds/*.{mp3,wav,...} to the R2 bucket "download"
# under keys: <prefix>/<id>.<ext>  (e.g. loops/ocean_waves.mp3).
#
# Re-running uploads everything that's not already in the bucket. Pretty
# URLs come at the cost of CDN cache staleness if you replace a file
# under the same key — purge the edge cache when that happens.
#
# Requires `wrangler` (npm i -g wrangler) and `wrangler login` once.
#
# Usage:
#   scripts/upload-sounds.sh                # upload all
#   scripts/upload-sounds.sh --dry-run      # print what would happen
#   BUCKET=download PREFIX=loops scripts/upload-sounds.sh
set -euo pipefail

SOUNDS_DIR="${SOUNDS_DIR:-Sources/Shuuchuu/Resources/sounds}"
BUCKET="${BUCKET:-download}"
PREFIX="${PREFIX:-loops}"
PUBLIC_BASE="${PUBLIC_BASE:-https://music.secure-app.download}"
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "unknown arg: $arg" >&2; exit 1 ;;
    esac
done

if ! command -v wrangler >/dev/null 2>&1 && ! command -v npx >/dev/null 2>&1; then
    echo "error: needs wrangler or npx in PATH" >&2
    exit 1
fi
if ! command -v ffprobe >/dev/null 2>&1; then
    echo "error: ffprobe required for bitrate detection (brew install ffmpeg)" >&2
    exit 1
fi

WRANGLER=(wrangler)
if ! command -v wrangler >/dev/null 2>&1; then
    WRANGLER=(npx wrangler)
fi

if [[ ! -d "$SOUNDS_DIR" ]]; then
    echo "error: $SOUNDS_DIR not found" >&2
    exit 1
fi

uploaded=0
skipped=0
total=0

shopt -s nullglob
prefix_clean="${PREFIX#/}"
prefix_clean="${prefix_clean%/}"

for f in "$SOUNDS_DIR"/*.{mp3,wav,m4a,caf,aif,aiff,flac}; do
    [[ -f "$f" ]] || continue
    total=$((total + 1))

    base=$(basename "$f")
    id="${base%.*}"
    ext="${f##*.}"

    raw_bps=$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=bit_rate -of csv=p=0 "$f" 2>/dev/null || true)
    if [[ -n "$raw_bps" && "$raw_bps" != "N/A" ]]; then
        kbps=$(awk -v b="$raw_bps" 'BEGIN{printf "%d", (b/1000)+0.5}')
        stem="${id}_${kbps}kbps"
    else
        stem="$id"
    fi

    if [[ -n "$prefix_clean" ]]; then
        key="${prefix_clean}/${stem}.${ext}"
    else
        key="${stem}.${ext}"
    fi
    bytes=$(stat -f%z "$f")

    # Idempotence: HEAD the public URL. 200 = already there, skip. Non-200 = upload.
    # (wrangler r2 has no `head`/`info` subcommand and `get --pipe` exits 0 on miss.)
    code=$(curl -sI -o /dev/null -w "%{http_code}" "${PUBLIC_BASE}/${key}" || echo 000)
    if [[ "$code" == "200" ]]; then
        echo "skip  $key  ($(basename "$f"), ${bytes}B) — already in bucket"
        skipped=$((skipped + 1))
        continue
    fi

    if [[ "$DRY_RUN" == 1 ]]; then
        echo "would-upload  $key  <- $(basename "$f")  (${bytes}B)"
        continue
    fi

    echo "upload  $key  <- $(basename "$f")  (${bytes}B)"
    "${WRANGLER[@]}" r2 object put "$BUCKET/$key" \
        --file "$f" \
        --content-type "audio/$ext" \
        --remote
    uploaded=$((uploaded + 1))
done

echo
echo "done. total=$total uploaded=$uploaded skipped=$skipped dry_run=$DRY_RUN"
