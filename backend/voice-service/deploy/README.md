# Deployment — voice-backend

Local build → systemd → port 8089 (WireGuard internal IP). HTTPS exposure
optional через nginx reverse proxy.

## Steps (one-shot install)

```bash
# 1. Release build
cd /root/projects/voice/backend/voice-service
swift build -c release

# 2. Provision env file
sudo cp deploy/voice-backend.env.example /etc/voice-backend.env
sudo chmod 600 /etc/voice-backend.env
sudo vim /etc/voice-backend.env
# set VOICE_BACKEND_TOKEN=$(openssl rand -hex 32)
# set VOICE_TARGET_CWD=/root/projects/cashflow
# set HAPPY_MODE=live   (explicit; or leave unset — defaults to live when cwd is set)
# optional: set STT_MODE=live + WHISPER_URL=… to wire /v1/voice/audio

# 3. Install unit + enable
sudo cp deploy/voice-backend.service /etc/systemd/system/voice-backend.service
sudo systemctl daemon-reload
sudo systemctl enable --now voice-backend

# 4. Verify
systemctl status voice-backend
journalctl -u voice-backend -f
```

## Smoke test

```bash
# Health: should return 401 (no auth on /, /v1/voice/intent requires Bearer)
curl -v http://127.0.0.1:8089/v1/voice/intent -X POST \
  -H "Content-Type: application/json" \
  -d '{"text":"hello","client_id":"smoke","ts":"2026-06-11T15:00:00.000Z"}'

# With valid token
curl -X POST http://127.0.0.1:8089/v1/voice/intent \
  -H "Authorization: Bearer $(grep VOICE_BACKEND_TOKEN /etc/voice-backend.env | cut -d= -f2)" \
  -H "Content-Type: application/json" \
  -d '{"text":"какой статус cashflow сегодня","client_id":"smoke","ts":"2026-06-11T15:00:00.000Z"}'
```

Expect: HTTP 200 с `{"reply":"...","latency_ms":N}`. В `HAPPY_MODE=live` —
из running Happy сессии для `VOICE_TARGET_CWD` (или 503 `backend_unavailable`
если её нет). В `HAPPY_MODE=echo` — `[echo reply] <text>` для smoke без
зависимости от Happy state.

## Modes recap

| HAPPY_MODE | STT_MODE | `/v1/voice/intent` | `/v1/voice/audio` |
|------------|----------|--------------------|-------------------|
| `live`     | `live`   | real Happy inject  | real Whisper (CUDA) |
| `live`     | `mock`   | real Happy inject  | echo bytes-count |
| `live`     | unset    | real Happy inject  | 503 stt_unavailable |
| `echo`     | `live`   | `[echo reply] …`   | real Whisper |
| unset      | unset    | echo (fallback)    | 503 |

STT и Happy режимы независимы — bumped в commit 2026-06-18 (B-Happy-bind),
до этого `STT_MODE=live` принудительно отключал real Happy inject.

## Logs

```bash
# JSONL request log (per-request audit trail)
tail -f /var/log/voice.jsonl | jq

# systemd journal (process stdout/stderr, startup errors)
journalctl -u voice-backend -f
```

## Update workflow

```bash
cd /root/projects/voice/backend/voice-service
git pull   # or rsync from dev machine
swift build -c release
sudo systemctl restart voice-backend
journalctl -u voice-backend -n 20
```

## WireGuard / public exposure

Default bind: `127.0.0.1:8089` (localhost only). For client (iPhone) access:

- **WireGuard**: client routes traffic via `wg0` interface, server bind to
  WG internal IP (e.g. `10.0.0.1:8089`) — set `VOICE_HOST=10.0.0.1` in env.
- **Public via nginx**: set `VOICE_HOST=127.0.0.1`, add nginx reverse proxy
  with HTTPS termination + token in `Authorization` (or rate-limit by IP).

Do not expose port 8089 публично без HTTPS proxy — Bearer token идёт plain.

## voice-agent-mac loop (mac-client/)

Проектная обвязка для end-to-end voice-loop с mac-home (не самим VDS
backend'ом). Флоу: mic → whisper STT → HTTPS POST `/v1/voice/intent` →
inject в Claude сессию → Stop hook → TTS wrapper → mp3 в `/srv/voice-out/`
→ mac polls → afplay. Собирается из четырёх файлов в `mac-client/`:

- `voice-mac-reply` — text-only JSON reply (без TTS)
- `voice-mac-reply-both` — Yandex TTS oggopus → ffmpeg mp3 + JSON
- `voice-mac-auto-reply.sh` — Claude Code Stop hook; парсит transcript,
  находит last `[voice-mac ...]` user msg, извлекает linked assistant
  reply через parentUuid walk, вызывает `voice-mac-reply-both`. Dedup
  через `/tmp/voice-mac-hook-last-{cid}.txt`.
- `caddy-snippet.conf` — reverse_proxy `/v1/voice/*` + file_server
  `/voice-out/*` для public exposure.

### Install

```bash
cd /root/projects/voice/backend/voice-service/deploy/mac-client
sudo ./install.sh
# затем 3 ручных шага из вывода:
#   - /etc/yandex_speechkit.env с API-KEY
#   - merge caddy-snippet.conf в /etc/caddy/Caddyfile + reload
#   - .claude/settings.json в target проекте: Stop hook на voice-mac-auto-reply.sh
```

Mac client (`t3-mac-fire-and-poll.py`) — отдельный артефакт (пока в
`/tmp/`, permanent путь не выбран). Config в
`~/.voice-agent-mac/config.json` с `voice_backend` URL + bearer token.
