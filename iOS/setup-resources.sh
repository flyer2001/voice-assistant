#!/usr/bin/env bash
# setup-resources.sh — копирует 32 WAV из assets/bench/ в iOS/VoiceAssistant/Resources/audio/
# для bundling в iOS app. Эти файлы НЕ в repo (по .gitignore — слишком большие).
#
# Запускать перед `xcodegen generate` на mac-home (или на любой машине с raw audio).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/assets/bench"
DST="$ROOT/iOS/VoiceAssistant/Resources/audio"

if [[ ! -d "$SRC/normalized" ]] || [[ ! -d "$SRC/gsm" ]]; then
  echo "ERR: assets/bench/normalized or gsm missing — run normalize-raw.sh + derive-gsm.sh first"
  exit 1
fi

mkdir -p "$DST/clean" "$DST/gsm"
cp "$SRC/normalized"/*.wav "$DST/clean/"
cp "$SRC/gsm"/*.wav "$DST/gsm/"

echo "Copied to $DST:"
echo "  clean: $(ls "$DST/clean" | wc -l)"
echo "  gsm:   $(ls "$DST/gsm" | wc -l)"
