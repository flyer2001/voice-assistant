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

Expect: HTTP 200 с `{"reply":"...","latency_ms":N}` если есть running Happy
session для `VOICE_TARGET_CWD`. Иначе 503 `backend_unavailable`.

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
