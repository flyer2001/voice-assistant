#!/usr/bin/env bash
# Проверка alias-таблицы voice-focus без побочных эффектов: TTS подменён
# заглушкой, focus.json пишется во временный каталог.
#
# Смысл: Whisper коверкает «фокус на voice» по-разному (замеры
# bench/whisper-accuracy — voice.sess, voice-sess, voice-agent, «войс с»),
# и каждый непокрытый вариант превращается в «не нашёл проект».
#
#   ./test_voice_focus.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/projects/voice" "$TMP/projects/myRep" "$TMP/projects/cashflow"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$2" > %s/tts.txt\n' "$TMP" > "$TMP/fake-tts"
printf '#!/usr/bin/env bash\nprintf "CLEARED\\n" > %s/tts.txt\n' "$TMP" > "$TMP/fake-clear"
chmod 755 "$TMP/fake-tts" "$TMP/fake-clear"

export VOICE_REPLY_TTS="$TMP/fake-tts"
export VOICE_FOCUS_CLEAR="$TMP/fake-clear"
export VOICE_FOCUS_PATH="$TMP/focus.json"
export VOICE_PROJECTS_DIR="$TMP/projects"

pass=0; failed=0
run() { rm -f "$TMP/tts.txt" "$TMP/focus.json"; "$HERE/voice-focus" 123 "$1" >/dev/null 2>&1; }

expect_focus() { # <ввод> <ожидаемый проект>
  run "$1"
  local got; got=$(sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p' "$TMP/focus.json" 2>/dev/null)
  if [ "$got" = "$VOICE_PROJECTS_DIR/$2" ]; then
    echo "ok    '$1' → $2"; pass=$((pass+1))
  else
    echo "FAIL  '$1' → ожидал $2, получил '${got:-ничего}'"; failed=$((failed+1))
  fi
}

expect_clear() {
  run "$1"
  if [ "$(cat "$TMP/tts.txt" 2>/dev/null)" = "CLEARED" ]; then
    echo "ok    '$1' → сброс фокуса"; pass=$((pass+1))
  else
    echo "FAIL  '$1' → ожидал сброс"; failed=$((failed+1))
  fi
}

expect_notfound() {
  run "$1"
  if [ -f "$TMP/focus.json" ]; then
    echo "FAIL  '$1' → не должен был переключить"; failed=$((failed+1))
  else
    echo "ok    '$1' → не нашёл, фокус не тронут"; pass=$((pass+1))
  fi
}

echo "--- канонические имена ---"
expect_focus voice voice
expect_focus myRep myRep
expect_focus cashflow cashflow

echo "--- русские алиасы ---"
expect_focus войс voice
expect_focus дневник myRep
expect_focus кэшфлоу cashflow
expect_focus кешфлоу cashflow

echo "--- реальные искажения Whisper (замеры 2026-08-01) ---"
expect_focus voice.sess voice
expect_focus voice-sess voice
expect_focus voice-agent voice
expect_focus "Voice.Sess" voice

echo "--- пунктуация и регистр ---"
expect_focus "Войс," voice
expect_focus VOICE voice

echo "--- сброс к диспетчеру ---"
expect_clear ассистент
expect_clear диспетчер
expect_clear assistant

echo "--- несуществующее не ломает фокус ---"
expect_notfound крокодил
expect_notfound ../etc

echo
echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
