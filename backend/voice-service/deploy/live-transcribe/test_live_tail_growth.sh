#!/usr/bin/env bash
# Тест вердикта «растёт ли запись». Инцидент 2026-10-08: упал ssh-туннель до
# mac-work, ffprobe не ответил, DUR стал 0, хвост шесть раз подряд увидел
# «не растёт» и закрыл живую запись — потеряли 14 минут дейлика живьём.
# Контракт: сбой ssh НЕ считается простоем и не двигает счётчик.
#
#   ./test_live_tail_growth.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_growth.sh"

FAIL=0
check() {  # check <ожидание> <ssh_rc> <dur> <pos> <chunk> <idle>
  local want=$1; shift
  local got; got="$(growth_verdict "$@")"
  if [ "$got" = "$want" ]; then echo "ok   $want  <- $*"
  else echo "FAIL хотел '$want', получил '$got'  <- $*"; FAIL=1; fi
}

# ssh упал (rc≠0 или пусто) — вердикт ssh_fail, idle не трогаем
check "ssh_fail 0" 255 ""  735 15 0
check "ssh_fail 3" 1   ""  735 15 3
check "ssh_fail 5" 0   ""  735 15 5      # ssh ок, но ffprobe ничего не отдал
# Шесть ssh-сбоев подряд НЕ закрывают запись (ровно инцидент 08.10)
check "ssh_fail 5" 255 ""  735 15 5
# Нормальный простой: счётчик растёт, на шестом — close
check "wait 1"  0 740 735 15 0
check "wait 5"  0 740 735 15 4
check "close 6" 0 740 735 15 5
# Данные есть — grow, счётчик сброшен
check "grow 0"  0 760 735 15 5
check "grow 0"  0 750 735 15 0           # ровно chunk — уже можно резать

[ "$FAIL" -eq 0 ] && echo "все проверки зелёные" || { echo "есть красные"; exit 1; }
