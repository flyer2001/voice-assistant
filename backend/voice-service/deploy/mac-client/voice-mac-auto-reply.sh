#!/bin/bash
# Stop hook: если в текущем transcript есть user-сообщение [voice-mac ...],
# отправить связанный с ним assistant-ответ через voice-mac-reply-both.
#
# Логика обхода — в voice_mac_auto_reply.py (рядом), чтобы её можно было
# тестировать: python3 test_voice_mac_auto_reply.py
#
# Claude Code Stop hook получает JSON payload на stdin с полем transcript_path.
set -euo pipefail

PAYLOAD=$(cat)
# jq на невалидном JSON выходит с ошибкой, а set -e уронил бы весь hook —
# Claude Code показал бы это как сбой Stop-хука. Молча выходим: чужой
# payload не наша забота. Поймано интеграционным тестом.
TRANSCRIPT=$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty' 2>/dev/null || true)
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

CORE="$(dirname "$(readlink -f "$0")")/voice_mac_auto_reply.py"
[ -f "$CORE" ] || exit 0

python3 "$CORE" "$TRANSCRIPT" &
disown $! 2>/dev/null || true
exit 0
