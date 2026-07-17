#!/bin/bash
# install.sh — copies voice-mac-* wrappers + Stop hook script to /usr/local/bin.
# Idempotent. Prints Caddy + Claude settings.json follow-ups but does NOT edit
# them (both are user infra, not code).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST=/usr/local/bin

for f in voice-mac-reply voice-mac-reply-both voice-mac-auto-reply.sh; do
  install -m 755 "$HERE/$f" "$DEST/$f"
  echo "installed $DEST/$f"
done

mkdir -p /srv/voice-out
chmod 755 /srv/voice-out
echo "ensured /srv/voice-out/ (mode 755)"

cat <<'EOF'

next steps (manual — not touched by this script):

  1. /etc/yandex_speechkit.env must contain: API-KEY=<yandex speechkit key>
     (chmod 600, root-only)

  2. Merge caddy-snippet.conf into the public host block in /etc/caddy/Caddyfile
     (see the snippet file for the two handle blocks). Then:
        sudo caddy validate --config /etc/caddy/Caddyfile
        sudo systemctl reload caddy

  3. Wire the Stop hook in the target project's .claude/settings.json:
        {
          "hooks": {
            "Stop": [{
              "matcher": ".*",
              "hooks": [{
                "type": "command",
                "command": "/usr/local/bin/voice-mac-auto-reply.sh",
                "timeout": 8
              }]
            }]
          }
        }

  4. Mac client (t3-mac-fire-and-poll.py) needs ~/.voice-agent-mac/config.json:
        { "voice_backend": "https://<host>", "bearer_token": "<VOICE_BACKEND_TOKEN>" }
EOF
