#!/usr/bin/env bash
# backup-voice-notes.sh — шифрованный бэкап конспектов созвонов.
# version: 2.0.0
# bumped: 2026-09-25
# bumped_reason: behavior change по приёмке agentops — три ложных зелёных
#   закрыты: (1) тревога при любом провале (её не было ВОВСЕ: крон писал в лог,
#   лог не читал никто); (2) пустой источник больше не «успех» (0 файлов в
#   архиве проходили проверку `n_arc < n_src` как 0<0); (3) успех признаётся
#   только по ФАКТИЧЕСКИ созданному сейчас файлу — при падении tar|gpg скрипт
#   отчитывался по вчерашнему/сегодняшнему файлу, лежавшему раньше.
#   Плюс `--verify-file <arc>` — проверить любой архив, в т.ч. скачанный с офсайта.
# prev: 1.0.0 (2026-09-25) — initial — /srv/voice-private лежал единственной копией на VDS
#
# ЗАЧЕМ. Конспекты рабочих созвонов (`/srv/voice-private/live/*.md`) не лежат
# в git осознанно: наружу их не отдаём. Из-за этого у них не было вообще
# никакой второй копии, а принцип Sergey — «VDS смертен, важное дублируется
# вне его».
#
# КАК. Готовый канал agentops не переизобретаем: складываем gpg-архив
# в `/root/backups/configs/`, откуда `bin/offsite-webdav.sh` по воскресеньям
# сам заливает всё `*.gpg` на Yandex WebDAV. Ни git, ни rclone, ни своего
# пульта к хранилищу здесь не нужно.
#
# Фраза — тот же секрет bws `config_backup_passphrase`, что у backup-configs.sh:
# один пароль на восстановление вместо второго, который забудется.
#
# Usage: backup-voice-notes.sh [--apply] [--verify]
#   без --apply — DRY-RUN: печатает, что заархивировал бы
#   --verify    — после создания расшифровать и сверить список файлов
#
# Восстановление:
#   gpg -d voice-notes-YYYY-MM-DD.tar.gz.gpg | tar xzf - -C /
#
# Exit: 0 ok · 2 нет источника / нет фразы / архив не создался
set -uo pipefail

SRC="${VOICE_NOTES_SRC:-/srv/voice-private}"
DEST="${VOICE_NOTES_DEST:-/root/backups/configs}"
# 8, а не 7: офсайт ходит раз в неделю (вс 06:30), и день, выпавший локально
# до его прогона, не уедет никогда. Запас в сутки закрывает эту щель.
KEEP="${VOICE_NOTES_KEEP:-8}"

# Тревога. Её не было вовсе — дыра, названная нами же при сдаче на приёмку:
# «крон молча пишет в лог, и лог никто не читает». Уровень notify (текст в ВК),
# не act: пропущенный бэкап конспектов — не пожар, но узнать о нём надо в тот
# же день, а не в день аварии.
NOTIFY="${VOICE_NOTES_NOTIFY:-/root/projects/agentops/bin/notify.sh}"
die() {  # die <сообщение> [код]
  echo "$1" >&2
  [[ -x "$NOTIFY" ]] && "$NOTIFY" notify "Бэкап конспектов созвонов НЕ сделан: $1" >/dev/null 2>&1 || true
  exit "${2:-2}"
}

APPLY=0 VERIFY=0 VERIFY_FILE=
while (($#)); do
  case "$1" in
    --apply)  APPLY=1;  shift ;;
    --verify) VERIFY=1; shift ;;
    --verify-file) VERIFY_FILE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "backup-voice-notes: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[[ -n "$VERIFY_FILE" ]] || [[ -d "$SRC" ]] || die "нет источника $SRC" 

if (( ! APPLY )) && [[ -z "$VERIFY_FILE" ]]; then
  echo "[dry-run] $SRC → $DEST/voice-notes-$(date +%F).tar.gz.gpg"
  du -sh "$SRC"
  find "$SRC" -type f | wc -l | xargs echo "  файлов:"
  echo "backup-voice-notes: dry-run — используй --apply"
  exit 0
fi

# Фраза живёт в переменной и уходит gpg подстановкой процесса — тот же приём,
# что в backup-configs.sh: временного файла нет вовсе, значит нечего забыть
# удалить после kill -9. В argv не передаётся никогда — argv виден в /proc всем.
PASSFILE="${CONFIG_BACKUP_PASSFILE:-}"
PASSPHRASE=""
if [[ -z "$PASSFILE" ]]; then
  if [[ -z "${BWS_ACCESS_TOKEN:-}" && -f "$HOME/.bitwarden/access.env" ]]; then
    set -a; . "$HOME/.bitwarden/access.env"; set +a
    BWS_ACCESS_TOKEN="${BWS_ACCESS_TOKEN:-${key:-}}"
  fi
  [[ -n "${BWS_ACCESS_TOKEN:-}" ]] || die "нет фразы: ни CONFIG_BACKUP_PASSFILE, ни bws-токена" 
  export BWS_ACCESS_TOKEN
  ID=$(bws secret list 2>/dev/null | jq -r '.[] | select(.key=="config_backup_passphrase") | .id')
  [[ -n "$ID" ]] || die "в bws нет секрета config_backup_passphrase" 
  PASSPHRASE=$(bws secret get "$ID" 2>/dev/null | jq -r .value)
  [[ -n "$PASSPHRASE" ]] || die "bws вернул пустую фразу" 
fi

gpg_enc() {  # gpg_enc <out-file>  (stdin = поток tar)
  if [[ -n "$PASSFILE" ]]; then
    gpg --batch --quiet --yes --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSFILE" -o "$1" 2>/dev/null
  else
    gpg --batch --quiet --yes --symmetric --cipher-algo AES256 \
        --passphrase-file <(printf '%s' "$PASSPHRASE") -o "$1" 2>/dev/null
  fi
}

gpg_dec() {  # gpg_dec <in-file>  (stdout = поток tar)
  if [[ -n "$PASSFILE" ]]; then
    gpg --batch --quiet --yes --decrypt --passphrase-file "$PASSFILE" "$1" 2>/dev/null
  else
    gpg --batch --quiet --yes --decrypt \
        --passphrase-file <(printf '%s' "$PASSPHRASE") "$1" 2>/dev/null
  fi
}

# Проверка отдельного архива: ради дня аварии — расшифровать то, что реально
# лежит на приёмнике, не создавая нового бэкапа.
if [[ -n "$VERIFY_FILE" ]]; then
  [[ -s "$VERIFY_FILE" ]] || die "нет архива $VERIFY_FILE"
  n=$(gpg_dec "$VERIFY_FILE" | tar tzf - 2>/dev/null | grep -vc '/$')
  (( n > 0 )) || die "архив $VERIFY_FILE не читается обратно (0 файлов)"
  echo "verify-file ok: $n файлов читаются из $VERIFY_FILE"
  exit 0
fi

mkdir -p "$DEST"; chmod 700 "$DEST"
ARC="$DEST/voice-notes-$(date +%F).tar.gz.gpg"

# 💣 ПУСТОЙ ИСТОЧНИК — НЕ УСПЕХ. Пустой каталог даёт валидный tar.gz и валидный
# gpg: на диске такой архив неотличим от здорового, а восстанавливать из него
# нечего. Прежняя проверка `n_arc < n_src` пропускала это как 0 < 0 — ровно тот
# зеркальный отказ, который приёмка и искала.
N_SRC=$(find "$SRC" -type f | wc -l)
(( N_SRC > 0 )) || die "в источнике $SRC ноль файлов — бэкапировать нечего"

# ponytail: tar пишет пути без ведущего /, восстановление — `tar xzf - -C /`.
# 💣 Пишем в ВРЕМЕННЫЙ файл и только потом переносим. Иначе `-s "$ARC"` не
# отличает «создан сейчас» от «лежал раньше»: при падении tar|gpg скрипт
# отчитывался успехом по архиву предыдущего прогона за то же число.
TMP_ARC="$ARC.part.$$"
trap 'rm -f "$TMP_ARC"' EXIT
tar czf - --absolute-names --warning=no-file-changed "$SRC" 2>/dev/null | gpg_enc "$TMP_ARC"
PIPE_RC=("${PIPESTATUS[@]}")
[[ -s "$TMP_ARC" ]] || die "архив не создался (tar rc=${PIPE_RC[0]}, gpg rc=${PIPE_RC[1]})"
mv -f "$TMP_ARC" "$ARC"
chmod 600 "$ARC"

if (( VERIFY )); then
  # Проверка не «файл есть», а «файл читается обратно»: битый gpg или пустой
  # tar выглядят на диске ровно как здоровый архив.
  n_arc=$(gpg_dec "$ARC" | tar tzf - 2>/dev/null | grep -vc '/$')
  if (( n_arc < N_SRC )); then
    die "verify НЕ сошёлся: в архиве $n_arc файлов, в источнике $N_SRC"
  fi
  echo "verify ok: $n_arc файлов читаются обратно"
fi

# Локальная ретенция. Удалённая не нужна: offsite-webdav.sh чистит только
# имена sessions-*, наши не трогает. Текстовые конспекты жмутся в десятки
# килобайт за день — приёмник этого не заметит годами.
# ponytail: дальний горизонт не считаем; если на WebDAV станет тесно, здесь
# место для «первый архив месяца — бессрочно», как в offsite-webdav.sh.
mapfile -t OLD < <(ls -1t "$DEST"/voice-notes-*.tar.gz.gpg 2>/dev/null | tail -n +$((KEEP + 1)))
((${#OLD[@]})) && rm -f "${OLD[@]}"

echo "backup-voice-notes: $(du -h "$ARC" | cut -f1) → $ARC (локально храним $KEEP)"
