#!/usr/bin/env bash
# Пишет системный звук чанками, которые подхватывает transcribe_chunks.py.
#
#   ./capture.sh ~/podlodka/chunks [длина_чанка_сек]
#
# Требует, чтобы системный звук был виден как устройство ВВОДА. На mac-home
# это BlackHole:
#   brew install --cask blackhole-2ch
# затем в «Настройка Audio-MIDI» собрать Multi-Output Device из наушников и
# BlackHole 2ch и выбрать его выходом системы — иначе звук уйдёт в перехват,
# но не в уши.
#
# На mac-work BlackHole не ставим (корпоративная машина), там путь через OBS.
set -euo pipefail

CHUNKS="${1:?куда складывать чанки}"
SECONDS_PER_CHUNK="${2:-30}"
DEVICE_NAME="${VOICE_CAPTURE_DEVICE:-BlackHole}"

export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
command -v ffmpeg >/dev/null || { echo "нет ffmpeg: brew install ffmpeg" >&2; exit 1; }

# avfoundation адресует устройства номером, а он меняется при подключении
# наушников или монитора. Ищем по имени на каждом запуске.
DEVICES="$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 || true)"
INDEX="$(echo "$DEVICES" | sed -n '/audio devices/,$p' \
         | grep -i "$DEVICE_NAME" | head -1 \
         | sed -E 's/.*\[([0-9]+)\].*/\1/')"

if [ -z "$INDEX" ]; then
  echo "не нашёл аудиоустройство «$DEVICE_NAME». Доступные:" >&2
  echo "$DEVICES" | sed -n '/audio devices/,$p' | head -10 >&2
  echo "" >&2
  echo "Если BlackHole не установлен: brew install --cask blackhole-2ch" >&2
  exit 1
fi

mkdir -p "$CHUNKS"
echo "пишу с устройства [$INDEX] «$DEVICE_NAME», чанки по ${SECONDS_PER_CHUNK}с в $CHUNKS"
echo "остановить — Ctrl+C"

# 16 кГц моно: ровно то, что ест whisper, и в разы меньше данных.
# reset_timestamps нужен, иначе каждый следующий чанк начинается не с нуля
# и часть плееров считает его битым.
exec ffmpeg -hide_banner -loglevel warning \
  -f avfoundation -i ":$INDEX" \
  -ar 16000 -ac 1 \
  -f segment -segment_time "$SECONDS_PER_CHUNK" -reset_timestamps 1 \
  "$CHUNKS/chunk-%03d.wav"
