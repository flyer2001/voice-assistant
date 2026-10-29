# Проверка уровня дорожек записи для live_tail.sh. Под тестом — test_levels.sh.
#
# 💣 28.10 на 1:1 с руководителем микрофон в OBS писал пустой источник: средний
# уровень −40 dB, пики-щелчки до 0 dB, речи нет. Узнали ПОСЛЕ эфира — реплики
# Sergey потеряны целиком, восстановить нечего. 22.10 то же самое было с
# системным звуком: устройство в сцене есть, звук в него не идёт (macOS теряет
# разрешение на захват при смене аудиоустройства).
#
# Пороги — решение Sergey 28.10: ниже −45 dB мёртвая, −45…−35 предупреждение.
# ⚠️ Старт НЕ блокируется (его же решение): ложное срабатывание не должно
# стоить записи эфира, поэтому вердикт только сообщается.
#
# Замеры живых дорожек за три дня: −25.1, −25.7, −31.9, −32.9, −38.3 dB.
# Мёртвая 22.10: −91 dB. Пустой источник 28.10: −40.1 dB.
#
# level_verdict <mean_db>            → ok | quiet | dead | absent
# level_line <n> <mean_db> <вердикт> → строка для шапки конспекта
# levels_measure <host> <rec> <track> <secs> → средний уровень дорожки, dB

LEVEL_DEAD_DB="${VOICE_LEVEL_DEAD_DB:--45}"
LEVEL_QUIET_DB="${VOICE_LEVEL_QUIET_DB:--35}"

level_verdict() {
  local db="$1"
  # «Дорожки нет» — это не «мёртвая»: пугать тревогой на пустом замере нельзя.
  [ -z "$db" ] && { echo absent; return; }
  [ "$db" = "-inf" ] && { echo dead; return; }
  awk -v db="$db" -v dead="$LEVEL_DEAD_DB" -v quiet="$LEVEL_QUIET_DB" '
    BEGIN {
      if (db + 0 == 0 && db !~ /^-?0*\.?0+$/) { print "absent"; exit }
      if (db <= dead)  { print "dead";  exit }
      if (db <  quiet) { print "quiet"; exit }
      print "ok"
    }'
}

level_line() {
  local n=$1 db=$2 verdict=$3
  case "$verdict" in
    dead)   printf 'дорожка %s: %s dB — мёртвая, речи нет (источник в OBS пустой?)' "$n" "$db" ;;
    quiet)  printf 'дорожка %s: %s dB — тихая, речь может срезаться гейтами' "$n" "$db" ;;
    ok)     printf 'дорожка %s: %s dB' "$n" "$db" ;;
    *)      printf 'дорожка %s: уровень не измерен' "$n" ;;
  esac
}

levels_measure() {
  local host=$1 rec=$2 track=$3 secs=$4
  # ffmpeg печатает volumedetect в stderr — забираем 2>&1 на хосте, иначе
  # по ssh приедет пустота. Окно ограничено: мерить весь растущий файл дорого.
  "${LEVELS_SSH_BIN:-ssh}" -n -o BatchMode=yes -o ConnectTimeout=15 "$host" \
    "export PATH=/opt/homebrew/bin:\$PATH; ffmpeg -t $secs -i '$rec' -map 0:a:$((track - 1)) -af volumedetect -f null - 2>&1" \
    2>/dev/null | sed -nE 's/.*mean_volume: (-?[0-9.]+|-inf) dB.*/\1/p' | head -1
}
