#!/usr/bin/env bash
# backup-voice-notes.sh — шифрованный бэкап конспектов созвонов.
# version: 1.0.0
# bumped: 2026-09-25
# bumped_reason: initial — /srv/voice-private лежал единственной копией на VDS
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

APPLY=0 VERIFY=0
while (($#)); do
  case "$1" in
    --apply)  APPLY=1;  shift ;;
    --verify) VERIFY=1; shift ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "backup-voice-notes: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[[ -d "$SRC" ]] || { echo "нет источника $SRC" >&2; exit 2; }

if (( ! APPLY )); then
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
  [[ -n "${BWS_ACCESS_TOKEN:-}" ]] || { echo "нет фразы: ни CONFIG_BACKUP_PASSFILE, ни bws-токена" >&2; exit 2; }
  export BWS_ACCESS_TOKEN
  ID=$(bws secret list 2>/dev/null | jq -r '.[] | select(.key=="config_backup_passphrase") | .id')
  [[ -n "$ID" ]] || { echo "в bws нет секрета config_backup_passphrase" >&2; exit 2; }
  PASSPHRASE=$(bws secret get "$ID" 2>/dev/null | jq -r .value)
  [[ -n "$PASSPHRASE" ]] || { echo "bws вернул пустую фразу" >&2; exit 2; }
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

mkdir -p "$DEST"; chmod 700 "$DEST"
ARC="$DEST/voice-notes-$(date +%F).tar.gz.gpg"

# ponytail: tar пишет пути без ведущего /, восстановление — `tar xzf - -C /`.
tar czf - --absolute-names --warning=no-file-changed "$SRC" 2>/dev/null | gpg_enc "$ARC"
[[ -s "$ARC" ]] || { echo "архив не создался" >&2; exit 2; }
chmod 600 "$ARC"

if (( VERIFY )); then
  # Проверка не «файл есть», а «файл читается обратно»: битый gpg или пустой
  # tar выглядят на диске ровно как здоровый архив.
  n_src=$(find "$SRC" -type f | wc -l)
  n_arc=$(gpg_dec "$ARC" | tar tzf - 2>/dev/null | grep -vc '/$')
  if (( n_arc < n_src )); then
    echo "verify НЕ сошёлся: в архиве $n_arc файлов, в источнике $n_src" >&2
    exit 2
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
