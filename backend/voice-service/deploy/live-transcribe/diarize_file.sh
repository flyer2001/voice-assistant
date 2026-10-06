#!/usr/bin/env bash
# Конспект с разметкой «кто говорит» из готовой записи.
#
#   ./diarize_file.sh 'mac-work:~/Movies/2026-10-06 12-52-39.mov' out.md
#   ./diarize_file.sh /srv/voice-private/live/rec.wav out.md
#
# Разбор ПОСЛЕ эфира, не живой: диаризация в потоке работает плохо, ей нужна
# вся запись, чтобы развести голоса по кластерам. Живой конспект — live_tail.sh.
#
# Что происходит: звук жмётся в 16 кГц mono, уезжает на ubuntu-home, там
# sherpa-onnx режет его на интервалы по говорящим, обратно приходит JSON с
# номерами спикеров. Дальше каждый интервал распознаётся отдельным запросом к
# whisper — поэтому у каждой реплики есть и автор, и текст.
#
# Имена: --names 'Speaker_00=Антон,Speaker_01=Даша'. Без них в конспекте
# останутся номера — модель имён не знает и узнать не может.
set -uo pipefail

SRC="${1:?файл записи (можно host:path) }"
OUT="${2:?куда писать конспект}"
NAMES=""
THRESHOLD="${VOICE_DIAR_THRESHOLD:-0.8}"
NUM_SPEAKERS="${VOICE_DIAR_SPEAKERS:--1}"
shift 2 || true
while [ $# -gt 0 ]; do
  case "$1" in
    --names) NAMES="${2:-}"; shift 2 ;;
    --threshold) THRESHOLD="${2:-}"; shift 2 ;;
    --speakers) NUM_SPEAKERS="${2:-}"; shift 2 ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
done

DIAR_HOST="${VOICE_DIAR_HOST:-ubuntu-home}"
DIAR_PY="${VOICE_DIAR_PY:-/mnt/win-share/Users/Serg/whisper-server/diarize.py}"
DIAR_VENV="${VOICE_DIAR_VENV:-/mnt/win-share/Users/Serg/diarize-venv/bin/python}"
WHISPER="${VOICE_WHISPER_URL:-http://192.168.88.13:8000}"
PROMPT_FILE="${VOICE_PROMPT_FILE:-}"
# Длиннее — меньше запросов к whisper, но реплики разных спикеров рискуют
# слипнуться; короче — точнее, но дороже. 30 с подобрано под дейлик.
MAX_SEG="${VOICE_DIAR_MAX_SEG:-30}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
WAV="$TMP/full.wav"

echo "$(date +%H:%M:%S) готовлю звук..."
if [[ "$SRC" == *:* ]] && [[ "$SRC" != /* ]]; then
  RHOST="${SRC%%:*}"; RPATH="${SRC#*:}"
  ssh -o BatchMode=yes "$RHOST" \
    "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; ffmpeg -nostdin -v error -i '$RPATH' -vn -ar 16000 -ac 1 -f wav -" \
    > "$WAV"
else
  ffmpeg -nostdin -v error -i "$SRC" -vn -ar 16000 -ac 1 -f wav -y "$WAV"
fi
[ -s "$WAV" ] || { echo "звук не извлёкся из $SRC" >&2; exit 3; }
DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WAV" | cut -d. -f1)"
echo "$(date +%H:%M:%S) звук готов: ${DUR}с"

echo "$(date +%H:%M:%S) диаризация на $DIAR_HOST (порог $THRESHOLD)..."
scp -q "$WAV" "$DIAR_HOST:/tmp/diarize-in.wav" || { echo "не скопировал wav на $DIAR_HOST" >&2; exit 11; }
# --hold: на длинной записи машина успевает уснуть между scp и запуском,
# и тогда CUDA-контекст whisper умирает ровно посреди разбора.
HOST_LEASE_HOLDER="${HOST_LEASE_HOLDER:-voice-diarize}" \
  /root/projects/agentops/bin/with-host.sh --hold "$DIAR_HOST" -- \
  ssh -o BatchMode=yes "$DIAR_HOST" \
    "$DIAR_VENV $DIAR_PY --threshold $THRESHOLD --num-speakers $NUM_SPEAKERS /tmp/diarize-in.wav" \
  > "$TMP/seg.json" 2>"$TMP/seg.err"
if [ ! -s "$TMP/seg.json" ]; then
  echo "диаризация не вернула сегментов:" >&2; head -5 "$TMP/seg.err" >&2; exit 11
fi

# Склейка соседних интервалов одного спикера и нарезка длинных: сырые
# сегменты бывают по полсекунды, и запрос к whisper на каждый «ага» —
# это сотни запросов на ровном месте.
python3 - "$TMP/seg.json" "$MAX_SEG" > "$TMP/merged.tsv" <<'PY'
import json, sys
segs = json.load(open(sys.argv[1]))
cap = float(sys.argv[2])
out = []
for s in segs:
    if out and out[-1][2] == s["speaker"] and s["start"] - out[-1][1] < 1.0 \
       and out[-1][1] - out[-1][0] < cap:
        out[-1][1] = s["end"]
    else:
        out.append([s["start"], s["end"], s["speaker"]])
for a, b, sp in out:
    while b - a > cap:
        print(f"{a:.2f}\t{a + cap:.2f}\t{sp}")
        a += cap
    if b - a > 0.4:   # короче — обрывки, whisper на них галлюцинирует
        print(f"{a:.2f}\t{b:.2f}\t{sp}")
PY
TOTAL="$(wc -l < "$TMP/merged.tsv")"
SPEAKERS="$(cut -f3 "$TMP/merged.tsv" | sort -u | tr '\n' ' ')"
echo "$(date +%H:%M:%S) сегментов к распознаванию: $TOTAL, спикеры: $SPEAKERS"

name_of() {  # Speaker_00 -> Антон, если задано
  local sp="$1" pair
  [ -z "$NAMES" ] && { printf '%s' "$sp"; return; }
  IFS=',' read -ra PAIRS <<< "$NAMES"
  for pair in "${PAIRS[@]}"; do
    [ "${pair%%=*}" = "$sp" ] && { printf '%s' "${pair#*=}"; return; }
  done
  printf '%s' "$sp"
}

PROMPT_ARG=()
[ -n "$PROMPT_FILE" ] && [ -f "$PROMPT_FILE" ] && \
  PROMPT_ARG=(-F "initial_prompt=$(cat "$PROMPT_FILE")")

printf '# Конспект с разметкой по спикерам\n\nЗапись: %s\nДиаризация: sherpa-onnx, порог %s\n\n---\n\n' \
  "$(basename "$SRC")" "$THRESHOLD" > "$OUT"

N=0
while IFS=$'\t' read -r FROM TO SP; do
  N=$((N + 1))
  LEN="$(python3 -c "print(f'{float('$TO')-float('$FROM'):.2f}')")"
  ffmpeg -nostdin -v error -ss "$FROM" -t "$LEN" -i "$WAV" -ar 16000 -ac 1 -f wav -y "$TMP/seg.wav"
  RESP="$(curl -s --max-time 120 -w $'\n%{http_code}' -F "audio=@$TMP/seg.wav" -F "lang_hint=ru" \
          "${PROMPT_ARG[@]}" "$WHISPER/transcribe")"
  CODE="${RESP##*$'\n'}"
  TEXT="$(printf '%s' "${RESP%$'\n'*}" | jq -r '.text // empty' 2>/dev/null)"
  # Таймкод и отбраковка мусора — одним питоном: на коротком или тихом куске
  # whisper дописывает титры («Продолжение следует», «Спасибо за просмотр»,
  # «Субтитры сделал...»). В живом конспекте это терпимо — видно по контексту,
  # а здесь мусор получает автора и выглядит настоящей репликой человека.
  # Поймано на прогоне 06.10. Проверка в питоне, а не в bash: tr не понижает
  # регистр кириллицы, а nocasematch зависит от локали, которой в окружении
  # фонового запуска может не быть.
  read -r TC KEEP <<<"$(python3 -c '
import re, sys
s = int(float(sys.argv[1]))
t = re.sub(r"[\s.!,…]+", "", sys.argv[2]).lower()
junk = ("продолжениеследует", "спасибо", "спасибозапросмотр", "вотвотвот")
keep = "0" if (t in junk or t.startswith(("субтитры", "редакторсубтитров"))) else "1"
print(f"{s//3600:02d}:{s%3600//60:02d}:{s%60:02d}", keep)
' "$FROM" "$TEXT")"
  [ "$KEEP" = "1" ] || TEXT=""

  if [ -n "$TEXT" ]; then
    printf '**[%s]** _%s:_ %s\n\n' "$TC" "$(name_of "$SP")" "$TEXT" >> "$OUT"
  elif [ "$CODE" != "200" ]; then
    echo "$(date +%H:%M:%S) [$TC] ОШИБКА whisper HTTP $CODE" >&2
  fi
  [ $((N % 20)) -eq 0 ] && echo "$(date +%H:%M:%S) ...$N/$TOTAL"
done < "$TMP/merged.tsv"

echo "$(date +%H:%M:%S) готово: $OUT"
grep -c '^\*\*\[' "$OUT" | xargs -I{} echo "реплик в конспекте: {}"
