#!/usr/bin/env bash
# nanny.sh — нянька live_tail.sh. Жила в scratchpad три сессии подряд, поэтому
# переехала в репозиторий: логика смещения уже не однострочная, а терять её
# вместе со сессией — значит каждый раз заново получать дубли в чате.
#
# Usage: VOICE_INJECT_SID=<sid> nanny.sh   (setsid nohup, без tmux)
#
# Нянька хвоста. Хвост умирает молча (ловили 24.09 дважды), поэтому следим и
# за процессом, и за свежестью лога.
# 💣 При перезапуске ОБЯЗАТЕЛЬНО считаем смещение: запись одна на дейлик и
# груминг, и хвост с POS=0 перегонит всё разобранное — дубли в конспекте и
# сотня инжектов в чат.
LOG=/srv/voice-private/live/tail.log
SID="${VOICE_INJECT_SID:?нужен VOICE_INJECT_SID}"
TAIL=/root/projects/voice/backend/voice-service/deploy/live-transcribe/live_tail.sh

offset() {  # секунды от начала текущей записи до «сейчас», по стенным часам мака
  local name now start
  name=$(ssh -o ConnectTimeout=8 mac-work 'ls -t ~/Movies/*.mov 2>/dev/null | head -1' 2>/dev/null | tail -1)
  [ -n "$name" ] || { echo 0; return; }
  name=$(basename "$name" .mov)
  now=$(ssh -o ConnectTimeout=8 mac-work 'date +%s' 2>/dev/null | tail -1)
  start=$(ssh -o ConnectTimeout=8 mac-work "date -j -f '%Y-%m-%d %H-%M-%S' '$name' +%s" 2>/dev/null | tail -1)
  if [ -n "$now" ] && [ -n "$start" ] && [ "$now" -gt "$start" ]; then
    # минус 30 с: лучше пере-распознать полминуты, чем потерять реплику на стыке
    echo $(( now - start - 30 ))
  else
    echo 0
  fi
}

while true; do
  sleep 30
  pgrep -f "live_tail.sh mac-work" >/dev/null \
    && [ $(( $(date +%s) - $(stat -c %Y "$LOG") )) -lt 90 ] && continue
  pkill -f "live_tail.sh mac-work"; sleep 2
  POS=$(offset)
  echo "$(date +%H:%M:%S) нянька: перезапуск хвоста со смещения ${POS}с" >> "$LOG"
  setsid nohup env \
    VOICE_REC_DIR='$HOME/Movies' VOICE_CHUNK_S=15 VOICE_INJECT_EVERY=2 \
    VOICE_START_POS="$POS" VOICE_INJECT_SID="$SID" \
    VOICE_PROMPT_FILE="${VOICE_PROMPT_FILE:-/root/projects/voice/bench/work/prompt.txt}" \
    "$TAIL" mac-work /srv/voice-private/live >> "$LOG" 2>&1 < /dev/null &
done
