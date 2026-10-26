#!/usr/bin/env bash
# Запись распознанного куска в конспект: отдельным файлом, потому что под
# тестом (как lib_growth.sh). Контракт один и важный: в конспект текст попадает
# ВСЕГДА, чем бы его ни признали. Эхо своего TTS помечается и не уходит в блок
# для сессии, но из расшифровки не исчезает — иначе ошибка фильтра означала бы
# потерянную минуту эфира, а не лишнюю метку.

# echo_verdict <текст> [каталог_tts]
# Печатает причину, если текст — эхо нашего TTS. Молчит, если это эфир.
# Фильтр недоступен или сломан — молчит: транскрипцию он ронять не вправе.
echo_verdict() {
  local text="$1" dir="${2:-}" filter why
  filter="${ECHO_FILTER_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/echo_filter.py}"
  [ -n "$text" ] || return 0
  [ -x "$filter" ] || [ -f "$filter" ] || return 0
  why="$(printf '%s' "$text" | python3 "$filter" ${dir:+--tts-dir "$dir"} 2>&1 >/dev/null)" \
    && printf '%s' "$why"
  return 0
}

# emit_block <файл> <таймкод> <метка> <текст> <причина_эха>
# Дописывает строку в конспект и печатает в stdout то, что должно уехать в
# блок для сессии (пусто для эха).
emit_block() {
  local out="$1" tc="$2" label="$3" text="$4" why="$5"
  if [ -n "$why" ]; then
    printf '**[%s]** _[эхо TTS]_ %s\n\n' "$tc" "$text" >> "$out"
    return 0
  fi
  if [ -n "$label" ]; then
    printf '**[%s]** _%s:_ %s\n\n' "$tc" "$label" "$text" >> "$out"
    printf '%s: %s' "$label" "$text"
  else
    printf '**[%s]** %s\n\n' "$tc" "$text" >> "$out"
    printf '%s' "$text"
  fi
}
