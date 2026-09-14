#!/usr/bin/env bash
# Живой конспект из записи OBS, которая ещё пишется.
#
#   ./live_tail.sh mac-work ~/podlodka-live.md
#
# OBS пишет в mkv — контейнер читается недописанным, поэтому каждые N секунд
# вытягиваем очередной кусок звука по ssh, распознаём через CUDA и дописываем
# в растущий файл. Возить весь растущий mkv по сети не надо: ffmpeg работает
# на маке, сюда летит только wav-кусок (~1 МБ на 30 с).
#
# Требует: ffmpeg на маке (есть, brew), whisper-эндпоинт на ubuntu-home.
set -uo pipefail

HOST="${1:?ssh-хост с записью}"
OUT="${2:?куда писать конспект}"
CHUNK_S="${VOICE_CHUNK_S:-20}"
# Каждые сколько чанков инжектить накопленное в сессию-слушателя.
# 4 чанка по 20с = блок ~80 секунд речи, ~30 инжектов на часовой доклад.
INJECT_EVERY="${VOICE_INJECT_EVERY:-4}"
INJECT_CWD="${VOICE_INJECT_CWD:-}"
INJECT="$HOME/projects/assistant/scripts/inject/inject.mjs"
WHISPER="${VOICE_WHISPER_URL:-http://192.168.88.13:8000}"
PROMPT_FILE="${VOICE_PROMPT_FILE:-}"
REC_DIR="${VOICE_REC_DIR:-\$HOME/Movies}"

FFMPEG_MAC="export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; ffmpeg"

# Самый свежий mkv/mov в каталоге записей — его OBS сейчас и пишет.
find_recording() {
  # find, а не ls по глобу: во-первых, на маке login-shell zsh и несматченный
  # глоб роняет всю команду; во-вторых, в ~/Movies лежат записи прошлых
  # месяцев — без фильтра по свежести хвост схватил бы январскую. Берём
  # только то, что менялось в последние 10 минут, то есть пишется сейчас.
  ssh -n -o BatchMode=yes -o ConnectTimeout=15 "$HOST" \
    "find $REC_DIR -maxdepth 1 \\( -name '*.mkv' -o -name '*.mov' \\) -mmin -10 2>/dev/null | head -1"
}

REC=""
until [ -n "$REC" ]; do
  REC="$(find_recording || true)"
  [ -n "$REC" ] && break
  echo "$(date +%H:%M:%S) жду появления записи в $REC_DIR на $HOST..."
  sleep 10
done
echo "$(date +%H:%M:%S) запись: $REC"

# Начало записи — из имени файла OBS ("2026-09-14 11-00-05.mkv"), чтобы
# таймкоды конспекта совпадали со стенными часами скриншотов.
BASE="$(basename "$REC")"
START_HHMMSS="$(echo "$BASE" | sed -nE 's/.*[ _]([0-9]{2})-([0-9]{2})-([0-9]{2})\..*/\1:\2:\3/p')"
[ -z "$START_HHMMSS" ] && START_HHMMSS="00:00:00"

[ -s "$OUT" ] || printf '# Живой конспект\n\nЗапись: %s (старт %s)\n\n---\n\n' \
  "$BASE" "$START_HHMMSS" > "$OUT"

POS=0
IDLE=0
BUF=""
BUF_FROM=""
CHUNKS_IN_BUF=0

flush_buffer() {
  [ -z "$BUF" ] && return 0
  if [ -n "$INJECT_CWD" ]; then
    node "$INJECT" --to-cwd "$INJECT_CWD" --message "[подлодка-live $BUF_FROM-$1]
[режим слушателя: не отвечай развёрнуто, только следи за листом ожидания.
Попадание — короткий сигнал Sergey голосом, промах — молчаливый ack.]

$BUF" >/dev/null 2>&1       && echo "$(date +%H:%M:%S) инжект блока $BUF_FROM-$1"       || echo "$(date +%H:%M:%S) инжект НЕ дошёл ($BUF_FROM-$1), текст остаётся в файле"
  fi
  BUF=""; BUF_FROM=""; CHUNKS_IN_BUF=0
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROMPT_ARG=()
[ -n "$PROMPT_FILE" ] && [ -f "$PROMPT_FILE" ] && \
  PROMPT_ARG=(-F "initial_prompt=$(cat "$PROMPT_FILE")")

while true; do
  # Сколько уже записано. ffprobe на недописанном mkv занижает длительность
  # безопасно — просто подождём следующего круга.
  DUR="$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$HOST" \
    "export PATH=/opt/homebrew/bin:\$PATH; ffprobe -v error -show_entries format=duration -of csv=p=0 '$REC'" \
    2>/dev/null | cut -d. -f1)"
  DUR="${DUR:-0}"

  if [ $((DUR - POS)) -lt "$CHUNK_S" ]; then
    IDLE=$((IDLE + 1))
    # Полторы минуты без новых данных — запись остановлена, доклад кончился.
    if [ "$IDLE" -ge 6 ]; then
      echo "$(date +%H:%M:%S) запись не растёт, заканчиваю"
      break
    fi
    sleep 15
    continue
  fi
  IDLE=0

  W="$TMP/c.wav"
  ssh -o BatchMode=yes -o ConnectTimeout=15 "$HOST" \
    "export PATH=/opt/homebrew/bin:\$PATH; ffmpeg -v error -ss $POS -t $CHUNK_S -i '$REC' -vn -ar 16000 -ac 1 -f wav -" \
    > "$W" 2>/dev/null
  if [ ! -s "$W" ]; then
    echo "$(date +%H:%M:%S) пустой кусок на $POS, повтор через 10с"
    sleep 10
    continue
  fi

  TEXT="$(curl -s --max-time 120 -F "audio=@$W" -F "lang_hint=ru" \
          "${PROMPT_ARG[@]}" "$WHISPER/transcribe" | jq -r '.text // empty')"

  TC=$(printf '%02d:%02d:%02d' $((POS/3600)) $((POS%3600/60)) $((POS%60)))
  if [ -n "$TEXT" ]; then
    printf '**[%s]** %s\n\n' "$TC" "$TEXT" >> "$OUT"
    echo "$(date +%H:%M:%S) [$TC] ${#TEXT} символов"
    [ -z "$BUF_FROM" ] && BUF_FROM="$TC"
    BUF="$BUF $TEXT"
    CHUNKS_IN_BUF=$((CHUNKS_IN_BUF + 1))
    [ "$CHUNKS_IN_BUF" -ge "$INJECT_EVERY" ] && flush_buffer "$TC"
  else
    echo "$(date +%H:%M:%S) [$TC] тишина/ошибка распознавания"
  fi
  POS=$((POS + CHUNK_S))
done
flush_buffer "$(printf '%02d:%02d:%02d' $((POS/3600)) $((POS%3600/60)) $((POS%60)))"
