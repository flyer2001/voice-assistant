#!/usr/bin/env bash
# Интеграционная проверка Stop hook: реальный voice-mac-auto-reply.sh
# получает настоящий payload и должен вызвать отправку с правильным текстом.
#
# Unit-тесты покрывают обход цепочки, но не сам shell-скрипт: чтение stdin,
# парсинг transcript_path, запуск python в фоне. Один раз это уже стоило
# молчащего hook'а в проде.
#
# Отправка подменяется заглушкой через VOICE_MAC_REPLY_CMD — настоящее
# голосовое Sergey'ю не уходит.
#
#   ./test_integration.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

# Заглушка вместо voice-mac-reply-both: пишет аргументы в файл.
cat > "$TMP/fake-reply" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$TMP_OUT/called-cid.txt"
printf '%s\n' "$2" > "$TMP_OUT/called-text.txt"
EOF
sed -i "s|\$TMP_OUT|$TMP|g" "$TMP/fake-reply"
chmod 755 "$TMP/fake-reply"

# Transcript с tool_result внутри ответа — сценарий, на котором hook молчал.
cat > "$TMP/transcript.jsonl" <<'EOF'
{"type":"user","uuid":"u1","parentUuid":null,"timestamp":"2026-08-01T10:00:01Z","promptSource":"cli","message":{"content":"[voice-mac client_id=integration-test]\nкакая погода"}}
{"type":"assistant","uuid":"a1","parentUuid":"u1","timestamp":"2026-08-01T10:00:02Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{}}]}}
{"type":"user","uuid":"t1","parentUuid":"a1","timestamp":"2026-08-01T10:00:03Z","toolUseResult":{"stdout":"ok"},"message":{"content":[{"type":"tool_result","content":"ok"}]}}
{"type":"assistant","uuid":"a2","parentUuid":"t1","timestamp":"2026-08-01T10:00:04Z","message":{"content":[{"type":"text","text":"Сейчас плюс восемнадцать."}]}}
EOF

export VOICE_MAC_REPLY_CMD="$TMP/fake-reply"
export VOICE_MAC_MARKER_DIR="$TMP"

echo "{\"transcript_path\":\"$TMP/transcript.jsonl\"}" | "$HERE/voice-mac-auto-reply.sh" \
  || fail "hook вернул ненулевой код"

for _ in $(seq 1 20); do [ -f "$TMP/called-text.txt" ] && break; sleep 0.2; done

[ -f "$TMP/called-text.txt" ] || fail "отправка не вызвана — hook смолчал"
got_text=$(cat "$TMP/called-text.txt")
got_cid=$(cat "$TMP/called-cid.txt")
[ "$got_cid" = "integration-test" ] || fail "client_id: ожидал integration-test, получил '$got_cid'"
[ "$got_text" = "Сейчас плюс восемнадцать." ] || fail "текст: получил '$got_text'"
echo "ok  отправка вызвана с верным client_id и текстом после tool-вызова"

# Повторный запуск на том же transcript — дедупликация должна промолчать.
rm -f "$TMP/called-text.txt"
echo "{\"transcript_path\":\"$TMP/transcript.jsonl\"}" | "$HERE/voice-mac-auto-reply.sh"
sleep 1
[ -f "$TMP/called-text.txt" ] && fail "дедупликация не сработала — отправил повторно"
echo "ok  повтор того же ответа не отправляется"

# Без voice-mac сообщения hook обязан молчать.
cat > "$TMP/plain.jsonl" <<'EOF'
{"type":"user","uuid":"u1","parentUuid":null,"timestamp":"2026-08-01T10:00:01Z","promptSource":"cli","message":{"content":"обычный текст"}}
{"type":"assistant","uuid":"a1","parentUuid":"u1","timestamp":"2026-08-01T10:00:02Z","message":{"content":[{"type":"text","text":"ответ"}]}}
EOF
echo "{\"transcript_path\":\"$TMP/plain.jsonl\"}" | "$HERE/voice-mac-auto-reply.sh"
sleep 1
[ -f "$TMP/called-text.txt" ] && fail "отправил на обычный чат, не на voice-mac"
echo "ok  на обычной переписке молчит"

# Битый payload не должен ронять hook — Stop-хук обязан отработать всегда.
echo '{"transcript_path":"/nope/missing.jsonl"}' | "$HERE/voice-mac-auto-reply.sh" \
  || fail "упал на несуществующем transcript_path"
echo "not json" | "$HERE/voice-mac-auto-reply.sh" \
  || fail "упал на невалидном payload"
echo "ok  битый payload не роняет hook"

echo
echo "4 passed"
