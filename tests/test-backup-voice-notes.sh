#!/usr/bin/env bash
# Контракт scripts/backup-voice-notes.sh — бэкап конспектов созвонов.
# Приёмка agentops 2026-09-25 (заказчик — voice-сессия).
#
# Предмет — БЭКАП, то есть прибор: главный отказ у него зеркальный — отчитаться
# об успехе на битом архиве. Поэтому мутация двусторонняя:
#   вниз  — портим архив/источник  -> обязан упасть и позвать человека
#   вверх — здоровый прогон        -> обязан промолчать (никаких тревог)
#
# Фразу в тестах берём файлом (CONFIG_BACKUP_PASSFILE), чтобы не ходить в bws.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/scripts/backup-voice-notes.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ $1 — $2"; FAIL=$((FAIL+1)); }

[ -x "$BIN" ] || { echo "нет исполняемого $BIN"; exit 1; }

mkdir -p "$TMP/src/live" "$TMP/dest"
printf 'фраза-для-тестов\n' > "$TMP/pass"
for i in 1 2 3; do printf 'конспект %s\nстрока два\n' "$i" > "$TMP/src/live/note-$i.md"; done
# файл с не-ASCII именем и пробелом: tar/gpg ломаются именно на таких
printf 'созвон\n' > "$TMP/src/live/созвон 2026-09-25.md"

cat > "$TMP/fake-notify.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFY_LOG"
EOF
chmod +x "$TMP/fake-notify.sh"
export NOTIFY_LOG="$TMP/notify.log"; : > "$NOTIFY_LOG"

run() { VOICE_NOTES_SRC="$TMP/src" VOICE_NOTES_DEST="$TMP/dest" \
        CONFIG_BACKUP_PASSFILE="$TMP/pass" VOICE_NOTES_NOTIFY="$TMP/fake-notify.sh" \
        VOICE_NOTES_KEEP="${KEEP_OVERRIDE:-8}" bash "$BIN" "$@" 2>&1; }

echo "case: здоровый прогон с --verify (мутация ВВЕРХ — тревог быть не должно)"
: > "$NOTIFY_LOG"
OUT=$(run --apply --verify); RC=$?
[ "$RC" = 0 ] && ok "exit 0" || bad "exit 0" "rc=$RC: $OUT"
ARC=$(ls "$TMP/dest"/voice-notes-*.tar.gz.gpg 2>/dev/null | head -1)
[ -s "$ARC" ] && ok "архив создан" || bad "архив" "пусто в $TMP/dest"
[ -s "$NOTIFY_LOG" ] && bad "закричал на здоровом" "$(cat "$NOTIFY_LOG")" || ok "тревог нет"

echo "case: восстановление ПОБАЙТНО, а не по числу файлов"
# Число файлов совпадает и у архива, где содержимое подменено: счёт файлов
# такую порчу не видит вовсе. Контракт: verify обязан сверять содержимое.
mkdir -p "$TMP/back" && gpg --batch --quiet --yes --decrypt \
  --passphrase-file "$TMP/pass" "$ARC" 2>/dev/null | tar xzf - -C "$TMP/back"
SRC_IN_ARC="$TMP/back${TMP}/src"
diff -r --brief "$TMP/src" "$SRC_IN_ARC" >/dev/null 2>&1 \
  && ok "распакованное совпадает с источником побайтно" \
  || bad "побайтная сверка" "$(diff -r --brief "$TMP/src" "$SRC_IN_ARC" 2>&1 | head -3)"

echo "case: мутация ВНИЗ — источник ПУСТ, а архив «успешен»"
# Пустой каталог даёт валидный tar.gz и валидный gpg: на диске такой архив
# выглядит здоровым, а восстанавливать из него нечего. Молчать тут нельзя.
mkdir -p "$TMP/empty"
: > "$NOTIFY_LOG"
OUT=$(VOICE_NOTES_SRC="$TMP/empty" VOICE_NOTES_DEST="$TMP/dest" \
      CONFIG_BACKUP_PASSFILE="$TMP/pass" VOICE_NOTES_NOTIFY="$TMP/fake-notify.sh" \
      bash "$BIN" --apply --verify 2>&1); RC=$?
[ "$RC" != 0 ] && ok "пустой источник — не успех (rc=$RC)" || bad "пустой источник" "отчитался успехом: $OUT"
[ -s "$NOTIFY_LOG" ] && ok "человека позвали" || bad "тревога" "провал проглочен молча"

echo "case: мутация ВНИЗ — фразы нет вовсе"
: > "$NOTIFY_LOG"
OUT=$(env -u BWS_ACCESS_TOKEN VOICE_NOTES_SRC="$TMP/src" VOICE_NOTES_DEST="$TMP/dest" \
      CONFIG_BACKUP_PASSFILE="$TMP/НЕТ-ТАКОГО" VOICE_NOTES_NOTIFY="$TMP/fake-notify.sh" \
      bash "$BIN" --apply 2>&1); RC=$?
[ "$RC" != 0 ] && ok "без фразы падаем (rc=$RC)" || bad "нет фразы" "сделал вид, что зашифровал: $OUT"
[ -s "$NOTIFY_LOG" ] && ok "человека позвали" || bad "тревога" "молча"

echo "case: мутация ВНИЗ — архив битый (verify обязан поймать)"
: > "$NOTIFY_LOG"
run --apply >/dev/null
ARC2=$(ls -1t "$TMP/dest"/voice-notes-*.tar.gz.gpg | head -1)
# 💣 Дописать хвост НЕ ГОДИТСЯ: gpg читает валидный префикс и выходит с 0
# (мусор после пакета он игнорирует), проверка оставалась зелёной. Портим то,
# что действительно портится в жизни — обрезаем файл (недокачка/обрыв заливки).
python3 - "$ARC2" <<'PY'
import sys, os
f = sys.argv[1]; n = os.path.getsize(f)
os.truncate(f, int(n * 0.6))
PY
: > "$NOTIFY_LOG"
OUT=$(VOICE_NOTES_SRC="$TMP/src" VOICE_NOTES_DEST="$TMP/dest" \
      CONFIG_BACKUP_PASSFILE="$TMP/pass" VOICE_NOTES_NOTIFY="$TMP/fake-notify.sh" \
      bash "$BIN" --verify-file "$ARC2" 2>&1); RC=$?
[ "$RC" != 0 ] && ok "обрезанный архив не проходит verify (rc=$RC)" || bad "обрезанный архив" "признан здоровым: $OUT"
[ -s "$NOTIFY_LOG" ] && ok "человека позвали и тут" || bad "тревога" "молча"

echo "case: локальная ретенция держит ровно KEEP штук"
for d in 01 02 03 04 05 06 07 08 09 10; do : > "$TMP/dest/voice-notes-2026-08-$d.tar.gz.gpg"; done
KEEP_OVERRIDE=3 run --apply >/dev/null
N=$(ls -1 "$TMP/dest"/voice-notes-*.tar.gz.gpg | wc -l)
[ "$N" = 3 ] && ok "осталось 3" || bad "ретенция" "осталось $N"

# --- режим --corpus (добавлено 29.09): корпус СТАТИЧЕН, поэтому главный отказ
# здесь другой — пересобирать архив на неизменном составе и гонять его в офсайт
# каждую ночь. Мутация вверх: второй прогон обязан промолчать и ничего не создать.
echo "case: --corpus создаёт архив и не пересоздаёт его на неизменном составе"
# фикстура повторяет РЕАЛЬНУЮ раскладку: скрипт ищет корпуса по путям внутри
# репозитория, и часть из них может отсутствовать — это не отказ
mkdir -p "$TMP/corpus/bench/podlodka/transcripts" "$TMP/corpus/bench/results"
printf 'расшифровка\n' > "$TMP/corpus/bench/podlodka/transcripts/talk.md"
printf 'производное\n' > "$TMP/corpus/bench/podlodka/transcripts/talk.wav"
printf 'замер\n' > "$TMP/corpus/bench/results/wer.json"
: > "$NOTIFY_LOG"
corpus() { VOICE_NOTES_SRC="$TMP/corpus" VOICE_NOTES_DEST="$TMP/dest" \
           VOICE_REPO="$TMP/corpus" CONFIG_BACKUP_PASSFILE="$TMP/pass" \
           VOICE_NOTES_NOTIFY="$TMP/fake-notify.sh" bash "$BIN" --corpus "$@" 2>&1; }
OUT=$(corpus --apply --verify); RC=$?
CARC=$(ls "$TMP/dest"/voice-corpus-*.tar.gz.gpg 2>/dev/null | head -1)
[ "$RC" = 0 ] && [ -s "$CARC" ] && ok "архив корпуса создан" || bad "корпус" "rc=$RC: $OUT"
# wav обязан быть исключён: он воспроизводится из mp3, место в офсайте не тратим
LIST=$(gpg --batch --quiet --decrypt --passphrase-file "$TMP/pass" "$CARC" 2>/dev/null | tar tzf - 2>/dev/null)
printf '%s' "$LIST" | grep -q '\.wav$' && bad "wav попал в архив" "$LIST" || ok "wav исключён"
OUT2=$(corpus --apply --verify); RC2=$?
N2=$(ls -1 "$TMP/dest"/voice-corpus-*.tar.gz.gpg | wc -l)
[ "$RC2" = 0 ] && [ "$N2" = 1 ] && ok "второй прогон ничего не создал" \
  || bad "идемпотентность" "rc=$RC2, архивов $N2: $OUT2"
printf 'ещё одна\n' > "$TMP/corpus/bench/podlodka/transcripts/talk2.md"
corpus --apply >/dev/null
printf '%s' "$(ls -1 "$TMP/dest"/voice-corpus-*.tar.gz.gpg | wc -l)" | grep -q '^1$' \
  && ok "после правки состава архив пересобран (то же имя за сутки)" \
  || bad "пересборка" "архивов $(ls -1 "$TMP/dest"/voice-corpus-*.tar.gz.gpg | wc -l)"
[ -s "$NOTIFY_LOG" ] && bad "закричал на здоровом корпусе" "$(cat "$NOTIFY_LOG")" || ok "тревог нет"

echo "── $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
