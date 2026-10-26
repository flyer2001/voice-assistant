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

# Ядро дописывает в существующий файл (живой записи так нужно для
# перезапуска), а здесь файл расшифровывается целиком — повтор начинаем с нуля,
# иначе блоки прошлого прогона задвоятся.
rm -f "$OUT"

# Ядро крутится в цикле и само не завершается — ждём, пока оно отчитается
# по каждому чанку (текст или тишина), и глушим. По росту выходного файла
# судить нельзя: тишина в него не пишется, и запись, начавшаяся с паузы,
# обрывалась на первых секундах (19.10, часовая встреча → 0 символов).
"$HERE/transcribe_chunks.py" "$WORK" "$OUT" \
  --chunk-seconds "$CHUNK" \
  --title "$(basename "${SRC%.*}")" 2> "$WORK/core.log" &
PID=$!

IDLE=0
LAST_DONE=0
while kill -0 "$PID" 2>/dev/null; do
  sleep 3
  DONE="$(grep -c ' чанк [0-9]*:' "$WORK/core.log" || true)"
  [ "$DONE" -ge "$TOTAL" ] && break
  if [ "$DONE" = "$LAST_DONE" ]; then
    IDLE=$((IDLE + 1))
    # Минута без единого чанка — распознавание встало (сеть, мёртвая CUDA).
    [ "$IDLE" -ge 20 ] && { echo "" >&2; tail -3 "$WORK/core.log" >&2; echo "встало на $DONE/$TOTAL" >&2; kill "$PID"; exit 1; }
  else
    IDLE=0
    LAST_DONE="$DONE"
    printf '\r  чанков %s/%s' "$DONE" "$TOTAL"
  fi
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

echo ""
echo "готово: $OUT ($(wc -c < "$OUT") символов)"
