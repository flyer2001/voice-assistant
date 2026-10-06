#!/usr/bin/env bash
# Визуальный слепок записи: что было на экране, когда это прозвучало.
#
#   ./screen_digest.sh 'mac-work:/Users/sgpopyvanov/Movies/<файл>.mov' out.md
#
# Разбор ПОСЛЕ эфира, по готовой записи. Нужен там, где содержание живёт на
# экране, а не в звуке: доклады, демонстрации, груминги с макетами. На дейлике
# бесполезен — там говорят, а не показывают.
#
# Кадры режутся на той машине, где лежит запись (возить видео по сети не надо),
# дубли отбрасываются по перцептивному хешу, у выживших снимается текст
# tesseract'ом. В конспект подклеивается по таймкоду.
#
# Требует: ffmpeg там, где запись; tesseract с русским языком и python3+PIL тут.
set -uo pipefail

SRC="${1:?запись (можно host:path)}"
OUT="${2:?куда писать слепок}"
STEP="${VOICE_SHOT_STEP:-20}"        # секунд между кадрами
# Ширина кадра. Апскейл информации не добавляет и только замедляет OCR,
# поэтому берётся min(ширина исходника, WIDTH). Узкое место не здесь, а в
# разрешении записи: при OBS 1280x720 мелкий шрифт в чужом интерфейсе не
# читается принципиально (проверено 06.10 на груминге).
WIDTH="${VOICE_SHOT_WIDTH:-1920}"
# Порог различия кадров (расстояние Хэмминга по 64-битному dhash). Меньше —
# больше кадров доживает до OCR. 8 отсекает дрожание курсора и видео в углу,
# но ловит смену слайда.
THRESHOLD="${VOICE_SHOT_THRESHOLD:-8}"
KEEP_DIR="${VOICE_SHOT_KEEP:-}"      # куда сложить выжившие кадры (по умолчанию не хранить)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/frames"

echo "$(date +%H:%M:%S) режу кадры раз в ${STEP}с..."
if [[ "$SRC" == *:* ]] && [[ "$SRC" != /* ]]; then
  RHOST="${SRC%%:*}"; RPATH="${SRC#*:}"
  ssh -o BatchMode=yes "$RHOST" "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH;
    D=\$(mktemp -d);
    ffmpeg -nostdin -v error -i '$RPATH' -vf \"fps=1/$STEP,scale='min(iw,$WIDTH)':-1\" -q:v 3 \"\$D/%04d.jpg\";
    COPYFILE_DISABLE=1 tar c -C \"\$D\" . ; rm -rf \"\$D\"" | tar x -C "$TMP/frames"
  # macOS tar кладёт рядом AppleDouble-файлы `._0001.jpg`. COPYFILE_DISABLE
  # отключает это на источнике, но если архив приехал со старого mac или из
  # другого tar — подчищаем и тут, иначе PIL падает на первом же таком файле.
  find "$TMP/frames" -name '._*' -delete
else
  ffmpeg -nostdin -v error -i "$SRC" -vf "fps=1/$STEP,scale='min(iw,$WIDTH)':-1" -q:v 3 "$TMP/frames/%04d.jpg"
fi

TOTAL=$(find "$TMP/frames" -name "*.jpg" -not -name "._*" | wc -l)
[ "$TOTAL" -gt 0 ] || { echo "кадров не получилось из $SRC" >&2; exit 3; }
echo "$(date +%H:%M:%S) кадров: $TOTAL"

# Отбор: оставляем только те, что заметно отличаются от последнего оставленного.
# Сравнение с ПОСЛЕДНИМ ОСТАВЛЕННЫМ, а не с предыдущим по порядку: иначе
# медленное наползание (анимация, постепенное появление списка) пройдёт как
# череда «почти одинаковых» и слайд потеряется целиком.
python3 - "$TMP/frames" "$THRESHOLD" "$STEP" > "$TMP/keep.tsv" <<'PY'
import sys, pathlib
from PIL import Image

frames = sorted(f for f in pathlib.Path(sys.argv[1]).glob("*.jpg")
                if not f.name.startswith("._"))
threshold, step = int(sys.argv[2]), int(sys.argv[3])

def dhash(path, size=8):
    img = Image.open(path).convert("L").resize((size + 1, size))
    bits = 0
    for y in range(size):
        for x in range(size):
            bits = (bits << 1) | (img.getpixel((x, y)) < img.getpixel((x + 1, y)))
    return bits

kept_hash = None
for i, f in enumerate(frames):
    h = dhash(f)
    if kept_hash is None or bin(h ^ kept_hash).count("1") >= threshold:
        kept_hash = h
        sec = i * step
        print(f"{f}\t{sec // 3600:02d}:{sec % 3600 // 60:02d}:{sec % 60:02d}")
PY

KEPT=$(wc -l < "$TMP/keep.tsv")
echo "$(date +%H:%M:%S) после отбора дублей: $KEPT"

printf '# Визуальный слепок\n\nЗапись: %s\nКадр раз в %sс, после отбора дублей осталось %s из %s.\n\n---\n\n' \
  "$(basename "$SRC")" "$STEP" "$KEPT" "$TOTAL" > "$OUT"

[ -n "$KEEP_DIR" ] && mkdir -p "$KEEP_DIR"
N=0
while IFS=$'\t' read -r FRAME TC; do
  N=$((N + 1))
  # --psm 4 — текст колонками: слайды и интерфейсы так читаются заметно лучше,
  # чем дефолтным 3, который ищет единый блок.
  TEXT="$(tesseract "$FRAME" - -l rus --psm 4 2>/dev/null | sed 's/[[:space:]]\+$//' | grep -v '^$')"
  WORDS=$(printf '%s' "$TEXT" | wc -w)
  if [ "$WORDS" -ge 3 ]; then
    printf '**[%s]**\n\n```\n%s\n```\n\n' "$TC" "$TEXT" >> "$OUT"
  else
    # Кадр без текста — картинка, схема или видео. Факт смены всё равно важен.
    printf '**[%s]** _(кадр без читаемого текста)_\n\n' "$TC" >> "$OUT"
  fi
  [ -n "$KEEP_DIR" ] && cp "$FRAME" "$KEEP_DIR/$TC.jpg"
  [ $((N % 10)) -eq 0 ] && echo "$(date +%H:%M:%S) ...$N/$KEPT"
done < "$TMP/keep.tsv"

echo "$(date +%H:%M:%S) готово: $OUT"
grep -c '^\*\*\[' "$OUT" | xargs -I{} echo "кадров в слепке: {}"
[ -n "$KEEP_DIR" ] && echo "кадры сохранены в $KEEP_DIR"
