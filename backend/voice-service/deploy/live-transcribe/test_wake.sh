#!/usr/bin/env bash
# Тест будильника хоста. Инцидент 28.10: ubuntu-home уснула под эфиром, хвост
# получал HTTP 000 на каждый чанк, нянька перезапускала его часами, и в чат не
# приходило НИЧЕГО — тишина выглядела точно как «эфир ещё не начался». Хуже
# того: хвост двигал позицию дальше на каждом отказе, то есть терял чанки
# безвозвратно, хотя запись на маке была цела.
# Контракт: серия отказов — это «хост спит», а не «подождём»; позиция не
# двигается, пока распознавание не вернулось.
#
#   ./test_wake.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_wake.sh"

FAIL=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; FAIL=1; }
eq() { [ "$3" = "$2" ] && ok "$1 = '$2'" || bad "$1: хотел '$2', получил '$3'"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── вердикт по коду ответа ──────────────────────────────────────────────────
# ok — распознавание живо, счётчик сброшен.
eq "200 сбрасывает счётчик"  "ok 0"    "$(wake_verdict 200 5 2)"
# 000 (нет ответа) и 5xx — отказ. Порог 2: один отказ бывает от сетевой
# икоты, два подряд — машина.
eq "первый отказ — ждём"     "retry 1" "$(wake_verdict 000 0 2)"
eq "второй отказ — будим"    "wake 2"  "$(wake_verdict 000 1 2)"
eq "500 тоже отказ"          "wake 2"  "$(wake_verdict 500 1 2)"
eq "502 тоже отказ"          "retry 1" "$(wake_verdict 502 0 2)"
# 4xx — это НЕ спящая машина, будить бесполезно: кривой запрос или промпт.
eq "400 не повод будить"     "bad 0"   "$(wake_verdict 400 1 2)"
eq "порог 1 — будим сразу"   "wake 1"  "$(wake_verdict 000 0 1)"

# ── позиция чанка ───────────────────────────────────────────────────────────
# Главный урон 28.10: позиция ехала вперёд на отказах, и куски эфира исчезали.
eq "успех — позиция едет"       "320" "$(pos_next 1 300 20)"
eq "отказ — позиция стоит"      "300" "$(pos_next '' 300 20)"
eq "тишина это успех, не отказ" "20"  "$(pos_next 1 0 20)"

# ── пробуждение ─────────────────────────────────────────────────────────────
# WoL и curl подменяем: тест не ходит в сеть и не будит настоящую машину.
WOL="$TMP/fake-wol"; printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$WOL_LOG"\nexit 0\n' > "$WOL"
chmod +x "$WOL"; export WOL_LOG="$TMP/wol.log"

# Здоровье: первый опрос мимо, второй — 200. Так ведёт себя реальная машина:
# замер 29.10 — ssh готов на 29-й секунде, /transcribe отвечает на 30-й.
CURL="$TMP/fake-curl"
cat > "$CURL" <<'SH'
#!/usr/bin/env bash
N=$(( $(cat "$CURL_N" 2>/dev/null || echo 0) + 1 ))
echo "$N" > "$CURL_N"
[ "$N" -ge 2 ] && echo 200 || echo 000
SH
chmod +x "$CURL"; export CURL_N="$TMP/curl.n"

if WAKE_LAN_BIN="$WOL" WAKE_CURL_BIN="$CURL" WAKE_POLL_S=0 \
   wake_host ubuntu-home http://h/health 30; then
  ok "хост разбужен: WoL + ожидание здоровья"
else
  bad "пробуждение провалилось, хотя здоровье вернулось"
fi
grep -q "ubuntu-home" "$WOL_LOG" && ok "WoL позван для нужной машины" \
  || bad "WoL не позван: $(cat "$WOL_LOG")"

# Потолок ожидания: машина не поднялась — отказ, а не вечное ожидание.
# Без потолка хвост висел бы молча, как 28.10.
DEAD="$TMP/dead-curl"; printf '#!/usr/bin/env bash\necho 000\n' > "$DEAD"; chmod +x "$DEAD"
if WAKE_LAN_BIN="$WOL" WAKE_CURL_BIN="$DEAD" WAKE_POLL_S=0 \
   wake_host ubuntu-home http://h/health 1; then
  bad "мёртвый хост отдал успех"
else
  ok "не поднялся за потолок — отказ"
fi

# WoL сам упал (нет утилиты, нет сети) — отказ, но не падение хвоста.
BROKEN="$TMP/broken-wol"; printf '#!/usr/bin/env bash\nexit 7\n' > "$BROKEN"; chmod +x "$BROKEN"
if WAKE_LAN_BIN="$BROKEN" WAKE_CURL_BIN="$DEAD" WAKE_POLL_S=0 \
   wake_host ubuntu-home http://h/health 1; then
  bad "сломанный WoL отдал успех"
else
  ok "сломанный WoL — отказ без падения"
fi

[ "$FAIL" -eq 0 ] && echo "все проверки зелёные" || { echo "есть красные"; exit 1; }
