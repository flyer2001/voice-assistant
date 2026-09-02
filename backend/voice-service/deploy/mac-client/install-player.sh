#!/usr/bin/env bash
# Ставит на mac-home LaunchAgent, который проигрывает ответы из /srv/voice-out/.
#
# LaunchAgent, а не ssh + afplay: из ssh-сессии CoreAudio недоступен, а
# launchctl asuser упирается в заблокированный экран. Агент стартует внутри
# графической сессии и потому звук слышен даже при закрытом экране.
#
# Лог: /tmp/voice-mac-player.log, ошибки: /tmp/voice-mac-player.err
# Перезапуск после правки скрипта:
#   launchctl kickstart -k gui/$(id -u)/com.flyer2001.voice-mac-player
#
# Запускать НА МАКЕ:
#   ./install-player.sh
#
# Переопределения: VOICE_CLIENT_ID=mac-home VENV=~/.venvs/voice-agent
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="${VENV:-$HOME/.venvs/voice-agent}"
BIN="${BIN:-$HOME/bin}"
LABEL="com.flyer2001.voice-mac-player"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CLIENT_ID="${VOICE_CLIENT_ID:-mac-home}"

PY="$VENV/bin/python"
[ -x "$PY" ] || PY="/usr/bin/python3"   # плееру хватает стандартной библиотеки

mkdir -p "$BIN" "$HOME/Library/LaunchAgents" "$HOME/.voice-agent-mac"
install -m 755 "$HERE/voice-mac-player.py" "$BIN/voice-mac-player.py"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PY</string>
        <string>$BIN/voice-mac-player.py</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>VOICE_CLIENT_ID</key>
        <string>$CLIENT_ID</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/voice-mac-player.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/voice-mac-player.err</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 2

echo "==> статус"
launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -E "state|pid" | head -3 \
  || echo "   агент не найден в списке"
echo "==> лог: /tmp/voice-mac-player.log"
tail -3 /tmp/voice-mac-player.log 2>/dev/null || echo "   лог пока пуст"

cat <<EOF

Готово. Проверка с VDS:
  voice-mac-reply-both $CLIENT_ID "проверка связи"

Остановить:  launchctl bootout gui/\$(id -u)/$LABEL
Запустить:   launchctl bootstrap gui/\$(id -u) $PLIST
EOF
