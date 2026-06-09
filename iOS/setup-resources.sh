#!/usr/bin/env bash
# setup-resources.sh — копирует 32 WAV из assets/bench/ в iOS/VoiceAssistant/Resources/audio/
# для bundling в iOS app. Эти файлы НЕ в repo (по .gitignore — слишком большие).
#
# Запускать перед `xcodegen generate` на mac-home (или на любой машине с raw audio).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/assets/bench"
# Audio in SPM library Resources/ → bundled via .process() in Package.swift
# accessible via Bundle.module in VoiceAssistant target.
DST="$ROOT/Sources/VoiceAssistant/Resources/audio"

if [[ ! -d "$SRC/normalized" ]] || [[ ! -d "$SRC/gsm" ]]; then
  echo "ERR: assets/bench/normalized or gsm missing — run normalize-raw.sh + derive-gsm.sh first"
  exit 1
fi

mkdir -p "$DST/clean" "$DST/gsm"
# Rename gsm files с prefix чтоб избежать name collision когда XcodeGen
# flattens hierarchy в bundle root (clean/1a-quiet.wav vs gsm/1a-quiet.wav).
for f in "$SRC/normalized"/*.wav; do
  cp "$f" "$DST/clean/$(basename "$f")"
done
for f in "$SRC/gsm"/*.wav; do
  cp "$f" "$DST/gsm/gsm-$(basename "$f")"
done

echo "Copied to $DST:"
echo "  clean: $(ls "$DST/clean" | wc -l)"
echo "  gsm:   $(ls "$DST/gsm" | wc -l)"
