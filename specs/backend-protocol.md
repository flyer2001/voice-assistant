# Backend protocol — v1

> Contract any backend implementation must honor for the voice client to
> work against it. **Self-contained.** No references to private
> infrastructure — concrete deployments (DispatcherAdapter,
> SlackAdapter, etc.) live in their own docs.
>
> Version: `v1`. Breaking changes bump to `v2` (new URL prefix).

---

## Endpoint

```
POST {BACKEND_URL}/v1/voice/intent
Content-Type: application/json
Authorization: Bearer {BACKEND_TOKEN}
```

`BACKEND_URL` is configured per-client. `BACKEND_TOKEN` is a static
bearer token issued by the backend operator and stored in the client
Keychain (iOS/macOS).

## Request body

```json
{
  "text": "что у меня по cashflow сегодня",
  "client_id": "iphone-15-sergey",
  "ts": "2026-06-07T14:23:01.123Z"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `text` | string | yes | Transcribed text from on-device STT. UTF-8. Non-empty. |
| `client_id` | string | yes | Free-form. Used by the backend for log routing and per-device rate limiting. |
| `ts` | string (ISO-8601 UTC) | yes | Client wall-clock at moment of send. Backend may use it for ordering / dedupe. |

## Response — success

```
HTTP 200 OK
Content-Type: application/json

{
  "reply": "по cashflow сегодня: 3 open issues, последний коммит — 4 часа назад",
  "latency_ms": 1840
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `reply` | string | yes | Text to render in the client bubble. Non-empty. Markdown allowed but client may strip. |
| `latency_ms` | integer | yes | Server-side processing time in milliseconds. For client observability. |

## Response — errors

| HTTP | Body shape | Client behavior |
|------|------------|----------------|
| `401` | `{"error": "unauthorized"}` | Token invalid. Show «check token» banner. Do not retry. |
| `403` | `{"error": "forbidden"}` | Token valid but action denied. Show error. Do not retry. |
| `429` | `{"error": "rate_limited", "retry_after_ms": 5000}` | Wait `retry_after_ms`, allow user to retry. |
| `503` | `{"error": "backend_unavailable"}` | Backend up but degraded. Show «backend down». Allow retry. |
| `5xx` (other) | `{"error": "internal"}` | Generic failure. Allow retry. |
| network error | n/a | Show «no connection». Allow retry. |

All error responses MUST include `Content-Type: application/json` and
the JSON `error` string field. Unknown error shape MUST be mapped by
the client to `BackendError.malformedResponse`.

## Timeouts

- Client request timeout: **15 seconds**. After 15s with no response
  client emits `BackendError.timeout`.
- Backend SHOULD return within 4s for the MVP UX budget (capture-to-bubble
  ≤ 4s total). 15s is the hard cap.

## Auth

Bearer token in `Authorization` header. Token is opaque to the client.
Backend MAY rotate tokens; client treats `401` as «reconfigure token».

No request signing in v1. If wire integrity becomes a concern, v2 may
add HMAC-SHA256 over body using a shared secret.

## Transport

- v1: HTTPS recommended for any public exposure. Plain HTTP acceptable
  only over a private network (WireGuard VPN tunnel, LAN).
- WebSocket / streaming partial transcripts: out of scope for v1. v2+
  may introduce `GET /v1/voice/stream` with WS upgrade.

## Idempotency

The endpoint is **not** idempotent. The backend MAY apply the same text
twice if the client retries. Clients SHOULD avoid retrying on `200` /
`4xx` (except `429`).

## Endpoint — voice audio in (added for S1)

```
POST {BACKEND_URL}/v1/voice/audio
Content-Type: multipart/form-data; boundary=…
Authorization: Bearer {BACKEND_TOKEN}
```

Receives raw audio from client, runs server-side STT, returns transcribed
text. Used by S1 (Speech echo) and downstream by S2 once the transcript
flows into `/v1/voice/intent`.

### Multipart fields

| Field | Required | Notes |
|---|---|---|
| `audio` | yes | Binary audio file. Accepted formats: `.caf`, `.wav`, `.ogg`, `.m4a`, `.mp3`. Server normalizes to 16 kHz mono PCM before STT. |
| `client_id` | yes | Free-form. Same semantics as `/v1/voice/intent`. |
| `ts` | yes | ISO-8601 UTC client wall-clock at upload start. |
| `lang_hint` | no | Optional BCP-47 (`ru`, `en`, `ru-RU`). Empty = auto-detect. Hint speeds up Whisper language detection. |
| `max_duration_s` | no | Client-side declared cap. Server still enforces hard 60s. |

### Response — success

```
HTTP 200 OK
Content-Type: application/json

{
  "text": "сколько денег на счету",
  "lang": "ru",
  "duration_s": 1.82,
  "stt_ms": 412,
  "stt_engine": "whisper-large-v3-turbo",
  "stt_source": "win-home"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `text` | string | yes | UTF-8. Can be empty string if STT got pure silence. |
| `lang` | string | yes | Detected (or hinted) BCP-47. |
| `duration_s` | number | yes | Audio length client uploaded. |
| `stt_ms` | integer | yes | STT processing time only (no network). |
| `stt_engine` | string | yes | Free-form, e.g. `whisper-large-v3-turbo`, `whisper-base`, `mock`. Client treats as opaque (for observability only). |
| `stt_source` | string | yes | Where STT ran (`win-home`, `vds-cpu`, `mock`). For observability. |

### Response — errors (audio endpoint specific)

| HTTP | Body shape | Client behavior |
|---|---|---|
| `400` | `{"error":"unsupported_format","accepted":[".caf",".wav","..."]}` | Show «формат не поддерживается». No retry. |
| `400` | `{"error":"audio_too_long","max_seconds":60,"got":85}` | Show «слишком длинно». No retry. |
| `400` | `{"error":"audio_too_short","min_ms":200}` | Show «слишком коротко». No retry. |
| `502` | `{"error":"stt_unavailable","reason":"win-home offline"}` | STT backend down, audio not processed. Allow retry. |
| `504` | `{"error":"stt_timeout","timeout_ms":30000}` | STT took too long. Allow retry. |

Common errors (`401` / `403` / `429` / `503` / `5xx`) follow the same
rules as `/v1/voice/intent` above.

### Timeouts (audio endpoint)

- Client request timeout: **30 seconds** (longer than `/v1/voice/intent`'s 15s — STT may run on CPU fallback).
- Backend SHOULD return within 5s for sub-10-sec audio under normal load.
- Max audio length hard cap: **60 seconds**.

### Storage

Backend MAY persist audio for debugging / re-transcription but MUST
delete within 24h unless user opted into longer retention. v1 default:
ephemeral (delete after STT completion). Privacy-first.

### Implementation notes (informational, not part of contract)

- Server-side normalization: `ffmpeg -i in.<ext> -ar 16000 -ac 1 -f wav -` before passing to Whisper.
- STT engine routing (decided at backend startup):
  1. If `WHISPER_URL` env set → forward audio to that URL (e.g., FastAPI on win-home)
  2. Else → run `whisper.cpp` locally (CPU fallback)
  3. Else → return `502 stt_unavailable`
- Mock mode for dev / tests: env `STT_MODE=mock` → returns `text="[mock] <bytes-count> bytes received"`, `stt_engine="mock"`.

## Versioning

`/v1/...` URL prefix is part of the contract. Breaking changes (renamed
fields, removed fields, changed types) require `/v2/...`. Additive
changes (new optional fields) stay on `v1`.

## Adapter implementations

This protocol is implemented by adapters living in
`Sources/voice/Backend/`. v0.0 ships one adapter:

- **DispatcherAdapter** — forwards to the author's private Hummingbird
  service which calls into Happy inject. Configuration:
  `BACKEND_URL=https://...` / `BACKEND_TOKEN=...`.

Planned adapters (post-MVP, separate documents):

- **RawHTTPAdapter** — generic backend implementing this protocol; for
  users who self-host.
- **SlackAdapter** — posts to a Slack webhook, reply pulled from thread.
- **OwnServerAdapter** — self-hosted Hummingbird without the
  Happy/dispatcher dependency.

Any new adapter MUST honor this protocol exactly. Diverging adapters
break the client; instead, propose a `v2` protocol bump.
