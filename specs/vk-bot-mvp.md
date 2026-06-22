# VK Bot MVP — E2E scenarios (для согласования)

> **Status**: DRAFT. Согласовать с Sergey → frozen → переходим в TDD ladder.
> **Scope**: voice in от Sergey через VK DM → Whisper STT → echo транскрипция
> + Happy inject → text reply в VK DM. **No TTS** (text-only reply на MVP).

## Архитектура — 1 sentence

`VKLongPollClient` (actor, AsyncHTTPClient) → events.poll → on `message_new`
с audio_message attachment → `VoiceMessagePipeline.handle(event)` → 3 things
in parallel: (a) save raw .ogg, (b) decide vk_transcript vs Whisper, (c) echo
to VK + inject в Happy + relay reply to VK. Audit JSONL each step.

## Файлы (предположительный)

```
backend/voice-service/Sources/VKAdapter/
  VKLongPollClient.swift       ← existing (V1 done, 16 tests)
  VKAPIClient.swift            ← existing (V0 done, 4 tests)
  VKModels.swift               ← existing (extend with AudioMessage shapes)
  VKEventParser.swift          ← existing (V2 done, 9 tests)
  VoiceMessagePipeline.swift   ← NEW (главный orchestrator)
  AudioStorage.swift           ← NEW (raw .ogg + audit.jsonl writer)
  TranscriptDecider.swift      ← NEW (vk vs whisper)
```

## Конфигурация (`/etc/voice-backend.env` extras)

```
VK_BOT_ENABLED=true
VK_BOT_TOKEN=<community access token, scope=messages,docs>
VK_GROUP_ID=<community id>
VK_OWNER_ID=<Sergey personal user_id, allowlist — only he can talk to bot>
VOICE_AUDIO_STORAGE=/var/lib/voice-bot/raw
VOICE_AUDIT_LOG=/var/lib/voice-bot/audit.jsonl
```

`VK_OWNER_ID` allowlist = guard от random users в community. Reject silently.

## E2E сценарии

### S-1 Happy path (VK transcript уже готов)

```
1. Sergey записывает 8s voice message в community DM.
2. VK Long Poll получает message_new {audio_message:
   {link_ogg, duration:8, transcript:"что у меня сегодня по cashflow",
    transcript_state:"done"}}.
3. Backend:
   a) GET link_ogg → save /var/lib/voice-bot/raw/2026-06-22T10-15-03-789-msg42.ogg
   b) Use VK transcript directly (state=done) → skip Whisper
   c) VK send: "👂 услышал: «что у меня сегодня по cashflow»"
   d) Happy inject в /root/projects/cashflow с body:
      "[voice from Sergey, src=vk-transcript, lang=ru]\nчто у меня сегодня по cashflow"
   e) Wait reply от Happy (timeout 30s)
   f) VK send: "<reply от Claude диспетчера>"
4. Audit: один JSONL line с timing breakdown.
```

**Latency budget**: 6-10s (download 1s + VK send echo 0.5s + Happy 4-6s + VK send reply 0.5s).

### S-2 Happy path (VK transcript ещё не готов — async)

```
1. Sergey записывает 15s voice message.
2. message_new приходит с transcript_state:"in_progress", transcript:"" или nil.
3. Backend:
   a) save .ogg
   b) State decision: НЕ ждать VK (slow + не guaranteed) → Whisper turbo.
   c) Whisper POST → text за ~1.2s.
   d) Echo + inject + reply — same as S-1.
4. Когда / если приходит audio_message_transcript event с финальной VK
   транскрипцией — записать в audit для **bench compare** (vk vs whisper
   WER), но не вмешиваться в живой flow.
```

### S-3 Whisper down

```
1. message_new audio_message без VK transcript.
2. Whisper POST → connection refused / 5xx.
3. Backend: VK send "⚠️ STT недоступен, audio сохранён, попробую позже" + audit log error.
4. Без Happy inject. Без reply. Audio остался на диске для retry.
```

**Retry**: NO automatic retry в MVP. Sergey решает re-record или wait. Ponytail: не строим retry queue до того как реально нужно.

### S-4 Happy session not running

```
1. Echo + Whisper OK.
2. HappyInjectMessenger.send → throws .state(noRunningSessionForCwd).
3. Backend: VK send "⚠️ диспетчер offline (нет running session в <cwd>),
   попробуй позже". Audit log.
```

### S-5 Happy inject succeeds, reply timeout

```
1. Echo + Whisper + inject OK.
2. JsonlWatcher 30s timeout (диспетчер занят).
3. Backend: VK send "⏳ диспетчер думает (>30s), отвечу позже" — НО we **don't**
   retry watch. Sergey увидит ответ через VK когда диспетчер сам инжектит
   ответ через отдельный outbound channel (Phase 2).
```

**Open question**: или подождать дольше (60s)? Sergey решает.

### S-6 Не-Sergey пишет боту

```
1. message_new от user_id != VK_OWNER_ID.
2. Backend: drop silently. Audit log с reason="not_allowlisted".
```

### S-7 Не-audio сообщение (текст / стикер / фото)

```
1. message_new без audio_message attachment.
2. Backend: ignore — не наш use case в MVP.
   Audit log с reason="not_audio".
```

**Open question**: или принимать текст напрямую (без STT) и инжектить?
Ponytail: пока нет, добавим если Sergey попросит.

### S-8 Audio слишком длинное

```
1. message_new audio_message с duration > 60s.
2. Backend: VK send "⚠️ audio > 60s, обрежь покороче или прислать как
   несколько сообщений". Drop. Audit log.
```

**Threshold 60s** — VK transcript reasonable upper bound. Whisper turbo
бы и 5min переварил, но Happy reply на 5-минутный monologue плохо.

## Audit log format (V10)

```jsonl
{"ts":"2026-06-22T10:15:03.789Z","msg_id":42,"peer_id":1234567,
 "audio_path":"/var/lib/voice-bot/raw/2026-06-22T10-15-03-789-msg42.ogg",
 "duration_s":8.2,
 "transcript_vk":"что у меня сегодня по cashflow",
 "transcript_whisper":null,
 "decision":"used_vk",
 "stt_ms":0,
 "inject_ms":3850,
 "vk_send_ms":480,
 "total_ms":4330,
 "happy_reply_chars":287,
 "outcome":"success"}
```

`transcript_vk` + `transcript_whisper` оба заполняются когда оба доступны
(S-2 with late audio_message_transcript) — для regression bench.

## Что **не** делаем в MVP

- TTS reply.
- Multi-session targeting (один target_cwd, hardcoded в env).
- Retry queue.
- Outbound «диспетчер сам шлёт voice/text Sergey'ю» (нужен webhook от
  диспетчера → voice service → VK).
- Rate limit / ban detection (VK retry-after handling).
- Group chat (только Sergey ↔ bot DM).
- Multilang (только RU; en автоматически если Whisper detect).
- Voice cloning, persona, intent classification.

## После approve

→ Phase 0 (spike checklist в TASKS) → Phase 2 TDD ladder:

1. RED E2E: `Tests/VKAdapterTests/VoiceMessagePipelineE2ETests.swift` —
   8 сценариев выше, через MockVKHTTPClient + MockWhisper + MockHappyInject.
2. RED component: TranscriptDecider, AudioStorage, VoiceMessagePipeline
   (отдельные suites).
3. RED unit: per-function tests, Triangulation.
4. GREEN ladder обратно.
