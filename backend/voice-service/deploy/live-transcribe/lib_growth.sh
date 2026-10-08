# Вердикт «растёт ли запись» для live_tail.sh. Вынесен в файл, чтобы его можно
# было прогнать тестом без запуска хвоста (test_live_tail_growth.sh).
#
# growth_verdict <ssh_rc> <dur> <pos> <chunk_s> <idle>  →  "<вердикт> <idle>"
#   ssh_fail — ffprobe по ssh не ответил: это не простой, счётчик не трогаем.
#              2026-10-08 упавший туннель шесть раз подряд дал DUR=0, и хвост
#              закрыл живую запись как «не растёт» — потеряли 14 минут дейлика.
#   wait     — данных меньше чанка, простой засчитан.
#   close    — шесть простоев подряд (полторы минуты) — запись остановлена.
#   grow     — есть чанк, можно резать; счётчик сброшен.
growth_verdict() {
  local rc=$1 dur=$2 pos=$3 chunk=$4 idle=$5
  if [ "$rc" -ne 0 ] || [ -z "$dur" ]; then
    echo "ssh_fail $idle"; return
  fi
  if [ $((dur - pos)) -lt "$chunk" ]; then
    idle=$((idle + 1))
    [ "$idle" -ge 6 ] && echo "close $idle" || echo "wait $idle"
    return
  fi
  echo "grow 0"
}
