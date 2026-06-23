# MVP — voice

> Scope первой итерации. Подробности по милстоунам — в `.claude/CHANGELOG.md`.
> Открытые задачи — в `.claude/TASKS.md`.

## DoD MVP

End-to-end **VK voice message → Whisper STT → Happy inject → text reply в VK** работает 24/7 на VDS. Без iOS клиента. Latency p50 ≤ 15с (3s audio → ~7s, 122s audio → ~10s).

**Реально достигнуто 2026-06-23** (см. CHANGELOG `MVP_thin² VK voice in / text out E2E green`). E2E зелёный, 95 backend tests, audit JSONL, 5 live messages обработаны.

## Pivot history

Изначальный план (`v0.0` → `v0.1` iOS/macOS клиент) **отложен в Phase 2**. Пивот на VK Bot transport 2026-06-19 — zero deployment на клиенте, Sergey уже использует VK для войсов, естественный канал.

## Phase 1 — Foundation (DONE 2026-06-08…06-18)

- ✅ v0.0 sellability foundation: repo, LICENSE placeholder, .gitignore, `BackendAdapter` protocol + `DispatcherAdapter`, `specs/backend-protocol.md`
- ✅ STT bench W1–W5: WhisperKit large-v3 vs Apple Speech vs faster-whisper. Winner: faster-whisper-large-v3-turbo на CUDA RTX 3070 (ubuntu-home dual-boot)
- ✅ Backend B1–B9: Hummingbird 2 service, `POST /v1/voice/intent`, Bearer auth, JSONL log, EnvComposition split
- ✅ S1 Speech echo + S2 Forward to Happy + bubble UI (iOS sim smoke green) — наработки legacy, reuse в Phase 5

## Phase 2 — VK Bot MVP_thin² (DONE 2026-06-23)

Pivot scope: **voice in / text out**, TTS skip полностью.

- ✅ Phase 0 spike SP1–SP5: VKModels audio_message verified, audio storage layout, VK creds wire, Happy target switch agentops → assistant
- ✅ Phase 2 TDD ladder: `TranscriptDecider`, `AudioStorage`, `VoiceMessagePipeline` orchestrator с closure-based DI (VKAdapter не depends на VoiceServiceCore)
- ✅ E2E scenarios S-1..S-8 mock'ами, 16 новых tests, **95/95 backend green**
- ✅ `main.swift` VK loop wire: `VK_BOT_ENABLED=true` → Long Poll forever loop, handles failed:2|3 via refetch
- ✅ `VOICE_MAX_AUDIO_S=300` env override (5 min = VK voice hard cap)
- ✅ VK Long Poll events enabled via `groups.setLongPollSettings`
- ✅ Live smoke E2E: 5 audit entries, latency p50 7-10s, msg182 122s OK

## Phase 3 — Operational hardening (current)

Цель — backend переживает reboot, без ручного ssh-rerun.

- ✅ **OP1**: Whisper FastAPI systemd unit на ubuntu-home (2026-06-23) — `/etc/whisper.env` + `/etc/systemd/system/whisper.service`, `RequiresMountsFor=/mnt/win-share`, `User=flyer2001`, `Restart=on-failure`. Smoke green: 3.12s audio → 674ms STT
- [ ] **OP3**: assistant Happy session keep-running на VDS

## Phase 4 — Dogfood / observability

- [ ] **DG1**: 5+ голосовых разных типов (short/long/code-mix/шумных) для bench audit. Cumulative WER vs VK-transcript
- [ ] **DG2**: Happy reply latency variance — msg179 (44s audio) дал `inject_ms=27.6s` outlier. Логировать prompt/output sizes
- [ ] **DG3**: VOICE_MAX_AUDIO_S=300 edge cases (290/295/305s)

## Phase 5 — iOS/macOS app (post-MVP, Backlog)

iOS клиент reuse VK transport как `BackendAdapter` impl. Phase 1 наработки (Turn/TurnsStore/Keychain/Onboarding) живые в `iOS/` + `Sources/VoiceAssistant/`. Детали — в `.claude/TASKS.md` Backlog.

## Phase 6+ — Backlog

- TTS reply (S3 Yandex SpeechKit Tier 1) — triggered только если text-out скучно после dogfood week
- Gemini LLM intent classifier (G0)
- v0.3 intent shortcuts (regex на VDS)
- iOS Shortcut, Apple Watch companion, SwiftData history
- Repo rename `voice` → бренд (перед public-share)
- License decision: AGPL-3.0 dual vs BSL vs proprietary

## Открытые риски (live)

- VK rate limit / ToS — Sergey ↔ bot DM only, ~100 msg/day fine (см. `reference_vk_bot_contracts.md`)
- VK `audio_message_transcript` async event skip'ается — Whisper всегда работает. Перепроверить если Whisper под нагрузкой
- Audit JSONL eviction NONE — ~180KB/msg, OK на год. Cleanup cron когда понадобится
