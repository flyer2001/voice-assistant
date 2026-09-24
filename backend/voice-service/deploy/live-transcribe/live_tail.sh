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
OUTDIR="${2:?каталог для конспектов}"
mkdir -p "$OUTDIR"
CHUNK_S="${VOICE_CHUNK_S:-20}"
# Каждые сколько чанков инжектить накопленное в сессию-слушателя.
# 4 чанка по 20с = блок ~80 секунд речи, ~30 инжектов на часовой доклад.
INJECT_EVERY="${VOICE_INJECT_EVERY:-4}"
INJECT_CWD="${VOICE_INJECT_CWD:-}"
# Точная адресация: sid надёжнее cwd, когда в каталоге живут две сессии —
# оркестратор и слушатель. По cwd блоки ушли бы в самую свежую, и после
# resume оркестратора адресат мог бы молча смениться.
INJECT_SID="${VOICE_INJECT_SID:-}"
INJECT="$HOME/projects/assistant/scripts/inject/inject.mjs"
WHISPER="${VOICE_WHISPER_URL:-http://192.168.88.13:8000}"
PROMPT_FILE="${VOICE_PROMPT_FILE:-}"
REC_DIR="${VOICE_REC_DIR:-\$HOME/Movies}"

FFMPEG_MAC="export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; ffmpeg"

# Pre-flight: доказать, что whisper РАБОТАЕТ, а не просто отвечает.
# /health отдаёт 200 и при мёртвом GPU — на этом 2026-09-24 потеряли дейлик
# и полчаса груминга. Прогон через модель ловит ровно тот отказ: при убитой
# после suspend CUDA приходит 500, при живой — 200 (текст пустой, звук-то
# тишина, но это уже доказывает, что модель отработала).
# Секунда тишины питоном: ffmpeg на VDS может не быть, wave — стдлиб.
preflight() {
  local wav="$1" resp code
  python3 -c "
import wave, sys
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(b'\x00\x00' * 16000)
" "$wav" 2>/dev/null || { echo "pre-flight: не смог собрать тестовый wav, пропускаю проверку"; return 0; }

  resp="$(curl -s --max-time 60 -w $'\n%{http_code}' -F "audio=@$wav" -F "lang_hint=ru" \
          "$WHISPER/transcribe" 2>/dev/null)"
  code="${resp##*$'\n'}"
  [ "$code" = "200" ] && { echo "$(date +%H:%M:%S) pre-flight: whisper распознаёт, поехали"; return 0; }

  echo "$(date +%H:%M:%S) pre-flight ПРОВАЛЕН: whisper вернул HTTP ${code:-нет ответа}"
  printf '%s\n' "${resp%$'\n'*}" | head -c 300
  echo
  echo "Чинить до старта эфира, иначе конспект будет пустым:"
  echo "  ssh ubuntu-home 'sudo rmmod nvidia_uvm && sudo modprobe nvidia_uvm'"
  echo "  ssh ubuntu-home 'sudo systemctl restart whisper'"
  echo "Диагностика целиком — ~/.claude/docs/live-transcribe.md"
  return 1
}

# Самый свежий mkv/mov в каталоге записей — его OBS сейчас и пишет.
find_recording() {
  # find, а не ls по глобу: во-первых, на маке login-shell zsh и несматченный
  # глоб роняет всю команду; во-вторых, в ~/Movies лежат записи прошлых
  # месяцев — без фильтра по свежести хвост схватил бы январскую. Берём
  # только то, что менялось в последние 10 минут, то есть пишется сейчас.
  # Сортировка по mtime обязательна: если OBS остановили и начали новую
  # запись, под фильтр свежести попадают ОБЕ, а find отдаёт их в порядке
  # каталога — без сортировки хвост цеплялся к остановленной.
  ssh -n -o BatchMode=yes -o ConnectTimeout=15 "$HOST" \
    "find $REC_DIR -maxdepth 1 \\( -name '*.mkv' -o -name '*.mov' \\) -mmin -10 -print0 2>/dev/null | xargs -0 stat -f '%m %N' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-"
}

# Без trap: дальше по коду свой trap на TMP, второй его перетрёт.
PREFLIGHT_WAV="$(mktemp -u)".wav
preflight "$PREFLIGHT_WAV"; PREFLIGHT_RC=$?
rm -f "$PREFLIGHT_WAV"
[ "$PREFLIGHT_RC" -eq 0 ] || exit 1

while true; do   # дежурный цикл: запись за записью

REC=""
until [ -n "$REC" ]; do
  CAND="$(find_recording || true)"
  if [ -n "$CAND" ] && [ ! -f "$OUTDIR/.done-$(basename "$CAND")" ]; then
    REC="$CAND"
    break
  fi
  echo "$(date +%H:%M:%S) жду новой записи в $REC_DIR на $HOST..."
  sleep 10
done
echo "$(date +%H:%M:%S) запись: $REC"

# Начало записи — из имени файла OBS ("2026-09-14 11-00-05.mkv"), чтобы
# таймкоды конспекта совпадали со стенными часами скриншотов.
BASE="$(basename "$REC")"
OUT="$OUTDIR/${BASE%.*}.md"
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
  if [ -n "$INJECT_SID" ] || [ -n "$INJECT_CWD" ]; then
    local TARGET_ARGS
    if [ -n "$INJECT_SID" ]; then TARGET_ARGS=(--to-sid "$INJECT_SID"); else TARGET_ARGS=(--to-cwd "$INJECT_CWD"); fi
    node "$INJECT" "${TARGET_ARGS[@]}" --message "[подлодка-live $BUF_FROM-$1]
[режим слушателя: молчаливый приём, сверка с листом ожидания.
Попадание — запись в questions.md + тихий текст в VK. Голосом — никогда:
Sergey в эфире, врывание в наушники запрещено его фидбеком 2026-09-14.]

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
    # Полторы минуты без новых данных — запись остановлена.
    if [ "$IDLE" -ge 6 ]; then
      echo "$(date +%H:%M:%S) запись не растёт, закрываю $BASE"
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

  # Код ответа нужен отдельно от тела: пустой .text при 200 — настоящая
  # тишина, пустой при 500 — сломанное распознавание. Раньше обе ситуации
  # писались в лог одной строкой, и поломка была невидима (2026-09-24:
  # CUDA умерла после suspend, /health продолжал отдавать 200, потеряли
  # дейлик целиком).
  RESP="$(curl -s --max-time 120 -w $'\n%{http_code}' -F "audio=@$W" -F "lang_hint=ru" \
          "${PROMPT_ARG[@]}" "$WHISPER/transcribe")"
  CODE="${RESP##*$'\n'}"
  BODY="${RESP%$'\n'*}"
  TEXT="$(printf '%s' "$BODY" | jq -r '.text // empty' 2>/dev/null)"

  TC=$(printf '%02d:%02d:%02d' $((POS/3600)) $((POS%3600/60)) $((POS%60)))
  if [ -n "$TEXT" ]; then
    printf '**[%s]** %s\n\n' "$TC" "$TEXT" >> "$OUT"
    echo "$(date +%H:%M:%S) [$TC] ${#TEXT} символов"
    [ -z "$BUF_FROM" ] && BUF_FROM="$TC"
    BUF="$BUF $TEXT"
    CHUNKS_IN_BUF=$((CHUNKS_IN_BUF + 1))
    [ "$CHUNKS_IN_BUF" -ge "$INJECT_EVERY" ] && flush_buffer "$TC"
  elif [ "$CODE" = "200" ]; then
    echo "$(date +%H:%M:%S) [$TC] тишина"
  else
    echo "$(date +%H:%M:%S) [$TC] ОШИБКА whisper HTTP $CODE: $(printf '%s' "$BODY" | head -c 200)"
  fi
  POS=$((POS + CHUNK_S))
done
flush_buffer "$(printf '%02d:%02d:%02d' $((POS/3600)) $((POS%3600/60)) $((POS%60)))"
touch "$OUTDIR/.done-$BASE"
POS=0; IDLE=0
echo "$(date +%H:%M:%S) готов к следующей записи"
done   # дежурный цикл
