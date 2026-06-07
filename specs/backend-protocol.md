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
