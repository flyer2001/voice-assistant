#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
D=../../backend/voice-service/deploy/live-transcribe
for f in audio/*.mp3; do
  n="$(basename "$f" .mp3)"
  out="transcripts/$n.md"
  [ -s "$out" ] && { echo "пропускаю $n (уже есть)"; continue; }
  echo "=== $n ==="
  VOICE_WHISPER_URL=http://192.168.88.13:8000 \
  VOICE_INITIAL_PROMPT="$(cat prompt.txt)" \
    "$D/transcribe_file.sh" "$f" "$out" 30
done
