#!/usr/bin/env bash
# Установка mac-части voice-agent на mac-home.
#
# Кладёт t3-скрипт в постоянное место (~/bin) и создаёт враппер, который
# зовёт его питоном из venv. Раньше скрипт жил в /tmp и пропадал после
# каждого reboot — 2026-08-01 именно так и обнаружилось, что окружение
# разобрано.
#
# Системный python на маке под PEP 668 (externally-managed), ставить в него
# pip-пакеты нельзя. Отсюда venv с --system-site-packages: mlx приходит из
# brew-питона, mlx-whisper ставится локально.
#
# Запускать НА МАКЕ:
#   ./install-mac.sh
#
# Переопределения: VENV=~/.venvs/voice-agent BIN=~/bin
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="${VENV:-$HOME/.venvs/voice-agent}"
BIN="${BIN:-$HOME/bin}"
PY_BOOT="${PY_BOOT:-/opt/homebrew/bin/python3.14}"

mkdir -p "$BIN"

if [ ! -x "$VENV/bin/python" ]; then
  echo "==> создаю venv $VENV (--system-site-packages, mlx берётся из brew)"
  "$PY_BOOT" -m venv --system-site-packages "$VENV"
fi

echo "==> pip install mlx-whisper"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet mlx-whisper

command -v ffmpeg >/dev/null || {
  echo "==> ffmpeg отсутствует, ставлю через brew (mlx_whisper без него не читает ogg)"
  brew install ffmpeg
}

echo "==> t3 → $BIN/"
install -m 755 "$HERE/t3-mac-fire-and-poll.py" "$BIN/t3-mac-fire-and-poll.py"

cat > "$BIN/voice-agent-t3" <<EOF
#!/usr/bin/env bash
# Сгенерировано install-mac.sh — правь установщик, не этот файл.
exec "$VENV/bin/python" "$BIN/t3-mac-fire-and-poll.py" "\$@"
EOF
chmod 755 "$BIN/voice-agent-t3"

echo "==> проверка"
"$VENV/bin/python" -c 'import mlx_whisper, mlx.core; print("   mlx_whisper ok, mlx", mlx.core.__version__)'
command -v ffmpeg >/dev/null && echo "   ffmpeg $(ffmpeg -version 2>/dev/null | head -1 | cut -d" " -f3)"
[ -f "$HOME/.voice-agent-mac/config.json" ] \
  && echo "   config.json на месте" \
  || echo "   ⚠ нет ~/.voice-agent-mac/config.json — создай (см. deploy/README.md)"

cat <<EOF

Готово. Запуск:
  $BIN/voice-agent-t3

Если ~/bin не в PATH — добавь в ~/.zshrc:
  export PATH="\$HOME/bin:\$PATH"
EOF
