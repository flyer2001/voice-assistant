#!/usr/bin/env bash
# Apple Voices (AVSpeechSynthesizer same engine as iOS).
# Generates AIFF via `say`, converts to MP3 with ffmpeg, writes metrics row.
#
# Usage: ./run_apple.sh [voice_name]
# Default voice: Milena (RU). Use 'say -v "?"' to list other voices.
set -euo pipefail

VOICE="${1:-Milena}"
PROVIDER="apple"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RESULTS_DIR="$REPO/bench/results/tts/$PROVIDER/$VOICE"
METRICS_CSV="$REPO/bench/results/tts/metrics.csv"
mkdir -p "$RESULTS_DIR"

if [ ! -f "$METRICS_CSV" ]; then
  echo "provider,voice,phrase_id,file_path,file_size_bytes,duration_s,latency_total_ms,cost_usd,notes" > "$METRICS_CSV"
fi

python3 -c "
import json, sys
with open('$SCRIPT_DIR/corpus.json') as f:
    data = json.load(f)
for p in data['phrases']:
    print(f\"{p['id']}\t{p['text']}\")
" | while IFS=$'\t' read -r PHRASE_ID TEXT; do
  AIFF="$RESULTS_DIR/$PHRASE_ID.aiff"
  MP3="$RESULTS_DIR/$PHRASE_ID.mp3"

  START_MS=$(python3 -c "import time; print(int(time.perf_counter()*1000))")
  say -v "$VOICE" -o "$AIFF" "$TEXT"
  END_MS=$(python3 -c "import time; print(int(time.perf_counter()*1000))")
  LATENCY=$((END_MS - START_MS))

  ffmpeg -y -loglevel error -i "$AIFF" -codec:a libmp3lame -b:a 96k "$MP3"
  rm "$AIFF"

  SIZE=$(stat -f%z "$MP3")
  DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$MP3" 2>/dev/null)

  echo "$PROVIDER,$VOICE,$PHRASE_ID,$MP3,$SIZE,$DURATION,$LATENCY,0.0,apple-builtin" >> "$METRICS_CSV"
  echo "  ✓ $PHRASE_ID  ${LATENCY}ms  $SIZE B  ${DURATION}s"
done

echo "Done: $RESULTS_DIR"
