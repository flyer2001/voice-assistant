#!/usr/bin/env bash
# backup-voice-notes.sh — шифрованный бэкап конспектов созвонов.
# version: 3.0.2
# bumped: 2026-09-25
# bumped_reason: patch — вычищены оставшиеся упоминания недельного офсайта
#   (канал суточный с 25.09); комментарий про удалённую ретенцию устарел: offsite-webdav
#   3.0.0 теперь чистит и voice-notes-*, политика у него, у нас только локальная
# prev: 3.0.0 (2026-09-25) — behavior change — добавлен второй источник: /srv/voice-out/accuracy
#   (корпус для замеров точности STT, часть записей живые за июнь — повторить
#   бенчмарк без них нельзя) и *.md из /srv/voice-out. Остальное в voice-out
#   расходное и НЕ бэкапится — это решение, а не умолчание. Snapshot v2.0.0.
# prev: 2.0.0 (2026-09-25) — behavior change по приёмке agentops — три ложных зелёных
#   закрыты: (1) тревога при любом провале (её не было ВОВСЕ: крон писал в лог,
#   лог не читал никто); (2) пустой источник больше не «успех» (0 файлов в
#   архиве проходили проверку `n_arc < n_src` как 0<0); (3) успех признаётся
#   только по ФАКТИЧЕСКИ созданному сейчас файлу — при падении tar|gpg скрипт
#   отчитывался по вчерашнему/сегодняшнему файлу, лежавшему раньше.
#   Плюс `--verify-file <arc>` — проверить любой архив, в т.ч. скачанный с офсайта.
#   1.0.0 (2026-09-25) — initial — /srv/voice-private лежал единственной копией на VDS
#
# ЗАЧЕМ. Конспекты рабочих созвонов (`/srv/voice-private/live/*.md`) не лежат
# в git осознанно: наружу их не отдаём. Из-за этого у них не было вообще
# никакой второй копии, а принцип Sergey — «VDS смертен, важное дублируется
# вне его».
#
# КАК. Готовый канал agentops не переизобретаем: складываем gpg-архив
# в `/root/backups/configs/`, откуда `bin/offsite-webdav.sh` каждую ночь
# сам заливает всё `*.gpg` на Yandex WebDAV (до 25.09 ходил по воскресеньям). Ни git, ни rclone, ни своего
# пульта к хранилищу здесь не нужно.
#
# Фраза — тот же секрет bws `config_backup_passphrase`, что у backup-configs.sh:
# один пароль на восстановление вместо второго, который забудется.
#
# Usage: backup-voice-notes.sh [--apply] [--verify] [--verify-file <arc>]
#   без --apply — DRY-RUN: печатает, что заархивировал бы
#   --verify    — после создания расшифровать и сверить число файлов
#   --verify-file <arc> — проверить готовый архив (например скачанный с офсайта),
#                 ничего не создавая
#
# Восстановление:
#   gpg -d voice-notes-YYYY-MM-DD.tar.gz.gpg | tar xzf - -C /
#
# Exit: 0 ok · 2 нет источника / нет фразы / архив не создался
set -uo pipefail

SRC="${VOICE_NOTES_SRC:-/srv/voice-private}"
DEST="${VOICE_NOTES_DEST:-/root/backups/configs}"
# Второй источник. `/srv/voice-out` целиком расходный — прогоны voice-agent,
# ogg и json, переживать их потерю не жалко. НО `accuracy/` — корпус для
# замеров точности STT, часть записей живые за июнь: потеряв его, повторить
# бенчмарк на тех же данных нельзя, а новые такие не запишешь. Туда же
# попал `podlodka-live.md` — конспект, оказавшийся не в своём каталоге.
# Переопределение VOICE_NOTES_SRC (тесты, разовый прогон) отключает добор:
# один явно названный источник — значит ровно он.
EXTRA=()
if [[ -z "${VOICE_NOTES_SRC:-}" ]]; then
  [[ -d /srv/voice-out/accuracy ]] && EXTRA+=(/srv/voice-out/accuracy)
  while IFS= read -r f; do EXTRA+=("$f"); done \
    < <(find /srv/voice-out -maxdepth 1 -type f -name '*.md' 2>/dev/null)
fi
# 8 держим при СУТОЧНОМ офсайте как ремень: хватило бы и меньшего, но если
# заливка снова станет недельной, ни один день не выпадет. Ровно на этом у
# configs-* в agentops была дыра 02.09-09.09 при KEEP=5.
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
  du -sh "$SRC" "${EXTRA[@]+"${EXTRA[@]}"}"
  find "$SRC" "${EXTRA[@]+"${EXTRA[@]}"}" -type f | wc -l | xargs echo "  файлов:"
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
N_SRC=$(find "$SRC" "${EXTRA[@]+"${EXTRA[@]}"}" -type f | wc -l)
(( N_SRC > 0 )) || die "в источнике $SRC ноль файлов — бэкапировать нечего"

# ponytail: tar пишет пути без ведущего /, восстановление — `tar xzf - -C /`.
# 💣 Пишем в ВРЕМЕННЫЙ файл и только потом переносим. Иначе `-s "$ARC"` не
# отличает «создан сейчас» от «лежал раньше»: при падении tar|gpg скрипт
# отчитывался успехом по архиву предыдущего прогона за то же число.
TMP_ARC="$ARC.part.$$"
trap 'rm -f "$TMP_ARC"' EXIT
tar czf - --absolute-names --warning=no-file-changed "$SRC" "${EXTRA[@]+"${EXTRA[@]}"}" 2>/dev/null | gpg_enc "$TMP_ARC"
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

# Локальная ретенция — только она наша. Удалённую с 2026-09-25 держит
# offsite-webdav.sh 3.0.0: он чистит и voice-notes-* (последние N + первый
# архив месяца + первый архив года бессрочно), поэтому правило «первый архив
# месяца» здесь заводить НЕ надо — будет два хозяина у одной политики.
# KEEP=8 при ежедневном офсайте — ремень: если офсайт снова станет недельным,
# ни один день не выпадет.
mapfile -t OLD < <(ls -1t "$DEST"/voice-notes-*.tar.gz.gpg 2>/dev/null | tail -n +$((KEEP + 1)))
((${#OLD[@]})) && rm -f "${OLD[@]}"

echo "backup-voice-notes: $(du -h "$ARC" | cut -f1) → $ARC (локально храним $KEEP)"
