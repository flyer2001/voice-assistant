#!/usr/bin/env bash
# normalize-raw.sh — iPhone Voice Memos .m4a → 16kHz mono float32 WAV
#
# iPhone пишет в AAC 44.1kHz stereo (или mono). Whisper/Gemma хотят 16kHz mono float32.
# Конвертация через ffmpeg: resample + downmix + sample_fmt change.
#
# Usage:
#   ./normalize-raw.sh assets/bench/raw assets/bench/normalized
#
# Input:  <src>/{1a,1b,2a,2b,3a,3b,4a,4b}-{quiet,noisy}.m4a  (16 files)
# Output: <dst>/{1a,1b,2a,2b,3a,3b,4a,4b}-{quiet,noisy}.wav  (16 files, 16kHz mono float32)

set -euo pipefail

SRC="${1:-assets/bench/raw}"
DST="${2:-assets/bench/normalized}"

if [[ ! -d "$SRC" ]]; then
  echo "ERR: source dir not found: $SRC" >&2
  exit 1
fi

mkdir -p "$DST"

TEXTS=(1a 1b 2a 2b 3a 3b 4a 4b)
ENVS=(quiet noisy)

processed=0
skipped=0
for text in "${TEXTS[@]}"; do
  for env in "${ENVS[@]}"; do
    name="${text}-${env}"
    in_file=""
    # try .m4a / .mp3 / .wav extensions
    for ext in m4a mp3 wav; do
      if [[ -f "$SRC/$name.$ext" ]]; then
        in_file="$SRC/$name.$ext"
        break
      fi
    done

    if [[ -z "$in_file" ]]; then
      echo "WARN: $name — no input file found, skip" >&2
      skipped=$((skipped + 1))
      continue
    fi

    out_file="$DST/$name.wav"
    echo "→ $in_file  →  $out_file"

    # -ar 16000        : resample to 16kHz
    # -ac 1            : mono (downmix if stereo)
    # -c:a pcm_f32le   : float32 little-endian PCM in WAV container (Whisper/Gemma native)
    # -y               : overwrite if exists
    ffmpeg -loglevel error -y -i "$in_file" \
      -ar 16000 -ac 1 -c:a pcm_f32le \
      "$out_file"

    processed=$((processed + 1))
  done
done

echo ""
echo "Done. Processed: $processed, skipped: $skipped (expected 16 total)"
