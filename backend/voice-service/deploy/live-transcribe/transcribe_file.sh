#!/usr/bin/env bash
# Расшифровывает готовую запись — доклад, созвон, что угодно с дорожкой звука.
#
#   ./transcribe_file.sh запись.mp4 [выход.md] [длина_чанка_сек]
#
# Тот же движок, что и у живой расшифровки, но без ожидания реального
# времени: файл нарезается целиком и обрабатывается подряд.
#
# Скорость по замеру: 122-секундная запись через CUDA — 25 секунд, то есть
# примерно впятеро быстрее реального времени. Часовой доклад — около
# 12 минут. Узкое место не распознавание (оно берёт чанк за 1-2 с), а
# последовательная обработка и накладные на каждый вызов. Если понадобится
# быстрее — распараллелить чанки, но для офлайна и так терпимо.
#
# Годится для видео: звуковая дорожка вынимается сама.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:?файл записи}"
OUT="${2:-${SRC%.*}.md}"
CHUNK="${3:-30}"

export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
command -v ffmpeg >/dev/null || { echo "нет ffmpeg" >&2; exit 1; }
[ -f "$SRC" ] || { echo "нет файла: $SRC" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC" 2>/dev/null || echo 0)"
echo "источник: $(basename "$SRC"), ${DUR%.*}с"
echo "режу на чанки по ${CHUNK}с..."

ffmpeg -hide_banner -loglevel error -i "$SRC" \
  -vn -ar 16000 -ac 1 \
  -f segment -segment_time "$CHUNK" -reset_timestamps 1 \
  "$WORK/chunk-%03d.wav"

TOTAL="$(ls "$WORK"/chunk-*.wav 2>/dev/null | wc -l | tr -d ' ')"
echo "чанков: $TOTAL"

# Ядро пропускает последний чанк, считая что в него ещё пишут. Для готового
# файла это не так — дописываем пустышку, чтобы настоящий последний обработался.
touch "$WORK/chunk-$(printf '%03d' "$TOTAL").wav"

# Ядро крутится в цикле и сам не завершается — ждём, пока перестанут
# появляться новые записи, и глушим.
"$HERE/transcribe_chunks.py" "$WORK" "$OUT" \
  --chunk-seconds "$CHUNK" \
  --title "$(basename "${SRC%.*}")" &
PID=$!

LAST_SIZE=0
STABLE=0
while kill -0 "$PID" 2>/dev/null; do
  sleep 3
  SIZE="$(wc -c < "$OUT" 2>/dev/null || echo 0)"
  if [ "$SIZE" = "$LAST_SIZE" ]; then
    STABLE=$((STABLE + 1))
    [ "$STABLE" -ge 4 ] && break
  else
    STABLE=0
    LAST_SIZE="$SIZE"
    printf '\r  распознано %s символов' "$SIZE"
  fi
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

echo ""
echo "готово: $OUT ($(wc -c < "$OUT") символов)"
