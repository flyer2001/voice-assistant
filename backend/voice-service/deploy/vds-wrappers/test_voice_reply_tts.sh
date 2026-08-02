#!/usr/bin/env bash
# Проверка voice-reply-tts без единого сетевого вызова: curl подменён
# заглушкой через PATH, секреты — фикстурами через env.
#
# Проверяем то, что реально срабатывало в проде: retry на «unknown error»
# от VK (наблюдалось 2026-08-01), внятные ошибки на каждом шаге цепочки,
# обрезка текста под лимит Яндекса.
#
#   ./test_voice_reply_tts.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo 'API-KEY=fake-yandex-key' > "$TMP/yandex.env"
echo 'VK_BOT_TOKEN=fake-vk-token' > "$TMP/vk.env"

export YANDEX_ENV_FILE="$TMP/yandex.env"
export VK_ENV_FILE="$TMP/vk.env"
export PATH="$TMP/bin:$PATH"
mkdir -p "$TMP/bin"

# Заглушка curl. Поведение задаётся файлами-флагами в $TMP.
cat > "$TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
args="$*"
echo "$args" >> "$TMPDIR_T/curl-calls.log"

# synthesize: пишем «аудио» в файл, указанный после -o
if [[ "$args" == *"tts:synthesize"* ]]; then
  out=""; prev=""
  for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
  if [ -f "$TMPDIR_T/fail-tts" ]; then printf 'x' > "$out"; else head -c 4096 /dev/zero > "$out"; fi
  exit 0
fi

if [[ "$args" == *"docs.getMessagesUploadServer"* ]]; then
  [ -f "$TMPDIR_T/fail-upserver" ] && { echo '{"error":{"error_msg":"no perms"}}'; exit 0; }
  echo '{"response":{"upload_url":"https://upload.example/x"}}'; exit 0
fi

if [[ "$args" == *"upload.example"* ]]; then
  n=$(cat "$TMPDIR_T/upload-count" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$TMPDIR_T/upload-count"
  need=$(cat "$TMPDIR_T/upload-fails" 2>/dev/null || echo 0)
  [ "$n" -le "$need" ] && { echo '{"error":"unknown error"}'; exit 0; }
  echo '{"file":"filetoken123"}'; exit 0
fi

if [[ "$args" == *"docs.save"* ]]; then
  [ -f "$TMPDIR_T/fail-save" ] && { echo '{"error":{"error_msg":"save failed"}}'; exit 0; }
  echo '{"response":{"audio_message":{"owner_id":777,"id":888}}}'; exit 0
fi

if [[ "$args" == *"messages.send"* ]]; then
  [ -f "$TMPDIR_T/fail-send" ] && { echo '{"error":{"error_msg":"send failed"}}'; exit 0; }
  echo '{"response":424242}'; exit 0
fi
echo '{}'
CURL
sed -i "s|\$TMPDIR_T|$TMP|g" "$TMP/bin/curl"
chmod 755 "$TMP/bin/curl"

pass=0; failed=0
reset() { rm -f "$TMP/fail-"* "$TMP/upload-count" "$TMP/upload-fails" "$TMP/curl-calls.log"; }
check() { # <описание> <ожидаемый код> <фактический код> [подстрока] [вывод]
  if [ "$2" != "$3" ]; then echo "FAIL  $1 — код $3, ждали $2"; failed=$((failed+1)); return; fi
  if [ -n "${4:-}" ] && [[ "${5:-}" != *"$4"* ]]; then
    echo "FAIL  $1 — нет '$4' в выводе"; failed=$((failed+1)); return
  fi
  echo "ok    $1"; pass=$((pass+1))
}

echo "--- удачный путь ---"
reset
out=$("$HERE/voice-reply-tts" 123 "привет" 2>&1); rc=$?
check "успешная отправка возвращает message_id" 0 "$rc" '"message_id":424242' "$out"

echo "--- retry на «unknown error» от VK (реальный случай 2026-08-01) ---"
reset; echo 2 > "$TMP/upload-fails"
out=$("$HERE/voice-reply-tts" 123 "привет" 2>&1); rc=$?
check "две неудачные загрузки — третья проходит" 0 "$rc" '"ok":true' "$out"
tries=$(cat "$TMP/upload-count")
[ "$tries" = "3" ] && { echo "ok    ровно 3 попытки"; pass=$((pass+1)); } \
  || { echo "FAIL  попыток $tries, ждали 3"; failed=$((failed+1)); }

reset; echo 9 > "$TMP/upload-fails"
out=$("$HERE/voice-reply-tts" 123 "привет" 2>&1); rc=$?
check "после 3 неудач — внятная ошибка" 1 "$rc" "upload failed after 3 attempts" "$out"

echo "--- ошибки на каждом шаге называются ---"
reset; touch "$TMP/fail-tts"
out=$("$HERE/voice-reply-tts" 123 "привет" 2>&1); rc=$?
check "пустой ответ синтеза не уходит в VK" 1 "$rc" "suspiciously small" "$out"

reset; touch "$TMP/fail-upserver"
out=$("$HERE/voice-reply-tts" 123 "привет" 2>&1); rc=$?
check "нет upload_url" 1 "$rc" "no upload_url" "$out"

reset; touch "$TMP/fail-save"
out=$("$HERE/voice-reply-tts" 123 "привет" 2>&1); rc=$?
check "docs.save провалился" 1 "$rc" "docs.save failed" "$out"

reset; touch "$TMP/fail-send"
out=$("$HERE/voice-reply-tts" 123 "привет" 2>&1); rc=$?
check "messages.send провалился" 1 "$rc" "messages.send failed" "$out"

echo "--- секреты ---"
reset
out=$(YANDEX_ENV_FILE=/nope/missing.env "$HERE/voice-reply-tts" 123 "привет" 2>&1); rc=$?
check "нет файла с ключом Яндекса" 1 "$rc" "API-KEY missing" "$out"
out=$(VK_ENV_FILE=/nope/missing.env "$HERE/voice-reply-tts" 123 "привет" 2>&1); rc=$?
check "нет файла с токеном VK" 1 "$rc" "VK_BOT_TOKEN missing" "$out"

echo "--- лимит длины Яндекса ---"
reset
long=$(head -c 6000 < /dev/zero | tr '\0' 'а')
out=$("$HERE/voice-reply-tts" 123 "$long" 2>&1); rc=$?
check "длинный текст обрезается, а не падает" 0 "$rc" "обрезаю" "$out"

echo "--- аргументы обязательны ---"
out=$("$HERE/voice-reply-tts" 2>&1); rc=$?
check "без peer_id — ошибка" 1 "$rc" "peer_id required" "$out"
out=$("$HERE/voice-reply-tts" 123 2>&1); rc=$?
check "без текста — ошибка" 1 "$rc" "text required" "$out"

echo
echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
