#!/usr/bin/env bash
# derive-gsm.sh — clean 16kHz WAV → telephone-band codec → 16kHz WAV
#
# Симулирует GSM voice path (HYP-045 IVR через звонок):
#  1. Downsample 16kHz → 8kHz (telephone band, Nyquist 4kHz режет all >4kHz)
#  2. Encode telephone codec (GSM 06.10 default, AMR-NB опционально если есть)
#  3. Decode back to PCM
#  4. Upsample to 16kHz (для совместимости с Whisper/Gemma input format)
#
# Контент уже потерян на шагах (1) и (2) — upsample на (4) только формат меняет.
#
# Codec choice:
#   - CODEC=gsm  (default): GSM 06.10 Full Rate, 8kHz, 13.2 kbps fixed.
#                Ubuntu ffmpeg includes via libgsm. Это classic 2G codec, более грубый
#                чем AMR-NB. Использовать как pessimistic baseline — если STT справится
#                на GSM 06.10, то на AMR-NB точно справится.
#   - CODEC=amrnb: AMR-NB, 4.75-12.2 kbps. Требует ffmpeg с libopencore_amrnb (отдельный
#                PPA в Ubuntu). Реалистичнее для современной GSM voice cell с Quectel EC25
#                и подобных USB модемов. Bitrate через AMRNB_BITRATE env (default 12.2k).
#
# Usage:
#   ./derive-gsm.sh assets/bench/normalized assets/bench/gsm
#   CODEC=amrnb ./derive-gsm.sh assets/bench/normalized assets/bench/amrnb
#
# Input:  <src>/{1a,1b,2a,2b,3a,3b,4a,4b}-{quiet,noisy}.wav  (16 files, 16kHz mono)
# Output: <dst>/{...}.wav  (16 files, 16kHz mono float32, codec-degraded content)

set -euo pipefail

SRC="${1:-assets/bench/normalized}"
DST="${2:-assets/bench/gsm}"
CODEC="${CODEC:-gsm}"
AMRNB_BITRATE="${AMRNB_BITRATE:-12.2k}"

if [[ ! -d "$SRC" ]]; then
  echo "ERR: source dir not found: $SRC" >&2
  exit 1
fi

# Capture encoder list once (avoid grep -q | SIGPIPE issues under set -o pipefail)
FFMPEG_ENCODERS=$(ffmpeg -hide_banner -encoders 2>/dev/null || true)

case "$CODEC" in
  gsm)
    if ! grep -qw libgsm <<< "$FFMPEG_ENCODERS"; then
      echo "ERR: ffmpeg missing libgsm encoder (apt install ffmpeg обычно включает)" >&2
      exit 1
    fi
    ENC_ARGS=(-ar 8000 -ac 1 -c:a libgsm)
    EXT="gsm"
    LABEL="GSM 06.10 Full Rate 13.2kbps"
    ;;
  amrnb)
    if ! grep -qw libopencore_amrnb <<< "$FFMPEG_ENCODERS"; then
      echo "ERR: ffmpeg missing libopencore_amrnb encoder" >&2
      echo "     Ubuntu universe не включает (license). Варианты:" >&2
      echo "       - PPA: ppa:savoury1/ffmpeg6 (или ppa:jonathonf/ffmpeg-6)" >&2
      echo "       - Build from source: --enable-libopencore-amrnb" >&2
      exit 1
    fi
    ENC_ARGS=(-ar 8000 -ac 1 -c:a libopencore_amrnb -b:a "$AMRNB_BITRATE")
    EXT="amr"
    LABEL="AMR-NB $AMRNB_BITRATE"
    ;;
  *)
    echo "ERR: unknown CODEC=$CODEC (supported: gsm, amrnb)" >&2
    exit 1
    ;;
esac

mkdir -p "$DST"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "Codec: $LABEL"
echo "Source: $SRC"
echo "Dest:   $DST"
echo ""

processed=0
for in_file in "$SRC"/*.wav; do
  [[ -f "$in_file" ]] || continue
  name=$(basename "$in_file" .wav)
  enc_tmp="$TMP/$name.$EXT"
  out_file="$DST/$name.wav"

  echo "→ $name  (16kHz clean → $LABEL → 16kHz)"

  # Step 1+2: 16kHz mono WAV → 8kHz mono encoded
  ffmpeg -loglevel error -y -i "$in_file" "${ENC_ARGS[@]}" "$enc_tmp"

  # Step 3+4: encoded → 16kHz mono float32 WAV (content already degraded)
  ffmpeg -loglevel error -y -i "$enc_tmp" \
    -ar 16000 -ac 1 -c:a pcm_f32le \
    "$out_file"

  processed=$((processed + 1))
done

echo ""
echo "Done. Processed: $processed files."
echo ""
echo "Sanity check (sample rate + channels + format of one output):"
ffprobe -hide_banner -v error -show_entries stream=sample_rate,channels,sample_fmt,duration \
  -of default=noprint_wrappers=1 "$DST"/*.wav 2>/dev/null | head -10 || true
