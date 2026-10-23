#!/usr/bin/env bash
# Собирает initial_prompt для whisper из docs/stt-glossary.md.
#
#   ./make-prompt.sh            # пишет prompt.txt рядом
#   ./make-prompt.sh --check    # только проверяет, что prompt.txt свежий
#
# Берёт секции, помеченные <!-- prompt:... -->, и склеивает в одну строку.
# Длиннее LIMIT символов — промпт начинает течь в расшифровку, поэтому отказ.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../../docs/stt-glossary.md"
OUT="$HERE/prompt.txt"
LIMIT=1200

TEXT="$(python3 - "$SRC" <<'PY'
import re, sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
out, grabbing = [], False
for line in lines:
    if re.match(r"\s*<!--\s*prompt:", line):
        grabbing = True
        continue
    if grabbing:
        if line.startswith("#"):          # началась следующая секция
            grabbing = False
        elif line.strip().startswith("-"):
            out.append(line.strip().lstrip("-").strip())
        elif line.strip():
            out.append(line.strip())
print(". ".join(s.rstrip(".") for s in out) + ".")
PY
)"

LEN="${#TEXT}"
if [ "$LEN" -gt "$LIMIT" ]; then
  echo "промпт $LEN символов — больше предела $LIMIT." >&2
  echo "Убери устаревшие термины в docs/stt-glossary.md, иначе промпт потечёт в текст." >&2
  exit 3
fi

if [ "${1:-}" = "--check" ]; then
  [ -f "$OUT" ] && [ "$TEXT" = "$(cat "$OUT")" ] \
    && { echo "prompt.txt свежий, $LEN символов"; exit 0; }
  echo "prompt.txt разошёлся с docs/stt-glossary.md — перегенерируй" >&2
  exit 2
fi

printf '%s' "$TEXT" > "$OUT"
echo "prompt.txt собран из docs/stt-glossary.md, $LEN символов (предел $LIMIT)"
