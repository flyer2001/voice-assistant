# Будильник хоста для live_tail.sh. Под тестом — test_wake.sh.
#
# 💣 28.10 ubuntu-home уснула под эфиром. Хвост получал HTTP 000 на каждый
# чанк, нянька перезапускала его часами, в чат не приходило ничего — и тишина
# в чате неотличима от «эфир ещё не начался». Потеряли живое распознавание 1:1
# целиком. Хуже: хвост двигал позицию вперёд на каждом отказе, то есть чанки
# уходили безвозвратно, хотя запись на маке была цела.
#
# Отсюда два правила:
#   - серия отказов = «хост спит», будим сами (замер 29.10: WoL + готовность
#     распознавания = 30 с, то есть цена пробуждения примерно один чанк);
#   - позиция не двигается, пока распознавание не вернулось.
#
# wake_verdict <http_code> <fails> <threshold> → "<ok|retry|wake|bad> <fails>"
# pos_next <got_ok> <pos> <chunk>              → новая позиция
# wake_host <host> <health_url> <cap_s>        → 0, если поднялся за потолок

wake_verdict() {
  local code=$1 fails=$2 threshold=$3
  case "$code" in
    200)       echo "ok 0"; return ;;
    # 4xx — машина жива, а запрос кривой (промпт, форма, размер). Будить
    # бесполезно, счётчик сна сбрасываем, чтобы не копить чужие отказы.
    4??)       echo "bad 0"; return ;;
  esac
  fails=$((fails + 1))
  [ "$fails" -ge "$threshold" ] && echo "wake $fails" || echo "retry $fails"
}

pos_next() {
  local got_ok=$1 pos=$2 chunk=$3
  # Тишина — это успех (whisper ответил 200 с пустым текстом), а не отказ:
  # на тишине позиция обязана ехать, иначе хвост встанет на паузе в докладе.
  [ -n "$got_ok" ] && echo $((pos + chunk)) || echo "$pos"
}

wake_host() {
  local host=$1 health=$2 cap=$3 waited=0 code
  local wol="${WAKE_LAN_BIN:-$HOME/projects/agentops/bin/wake-lan.sh}"
  local curl_bin="${WAKE_CURL_BIN:-}"
  local poll="${WAKE_POLL_S:-3}"

  "$wol" "$host" >/dev/null 2>&1 || true   # WoL мог не сработать — решает здоровье

  while :; do
    if [ -n "$curl_bin" ]; then
      code="$("$curl_bin" "$health" 2>/dev/null)"
    else
      code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$health" 2>/dev/null)"
    fi
    [ "$code" = "200" ] && return 0
    [ "$waited" -ge "$cap" ] && return 1   # потолок: не ждать молча, как 28.10
    sleep "$poll"
    waited=$((waited + poll + 1))
  done
}
