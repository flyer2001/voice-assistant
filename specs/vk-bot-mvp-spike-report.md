# Phase 0 Spike Report — 2026-06-22

## SP1 — VK audio_message shape ✅

**Source**: `Sources/VKAdapter/VKModels.swift` + memory `reference-vk-bot-contracts.md`
(research 2026-06-11, cross-checked vk-io TS types).

`VKAudioMessage` уже Codable со всеми полями:
```swift
id: Int64
ownerId: Int64
duration: Int
linkOgg: String
linkMp3: String?
accessKey: String?
transcript: String?
transcriptState: String?  // "done" | "error" | nil
```

Live VK API probe не нужен — contracts стабильны, cross-implementation
(Python/Node/Go SDK) подтверждают shape. Первый реальный voice от Sergey
покажет если есть delta.

## SP2 — transcript_state lifecycle ⚠️ MVP-decision принят

VK иногда шлёт async event `audio_message_transcript` (отдельный update type)
с финальной транскрипцией через секунды-минуты после `message_new`.

**Текущий парсер** (`VKEventParser.parse`): обрабатывает только `message_new`.
Async event игнорируется (попадёт в `.ignored(.unsupportedType("audio_message_transcript"))`).

**MVP decision**: НЕ ждать async VK transcript. Если на момент `message_new`
`transcript_state != "done"` → сразу гнать в Whisper. Async transcript можно
**отложить в Phase 2 audit** (записать в audit.jsonl для bench WER compare,
но не вмешиваться в живой flow). На MVP — skip.

Trade-off: иногда платим Whisper compute когда VK сделал бы бесплатно. RTX 3070
+ 14.6s sample → 756ms. Acceptable cost для предсказуемости.

## SP3 — Audio storage layout ✅

Создано на VDS:
```
/var/lib/voice-bot/                drwxr-x--- root:root
├── raw/                           drwxr-x---  (only voice-backend writes)
└── audit.jsonl                    -rw-r----- (append-only)
```

Disk: `/var/lib` на root partition, 23G free / 59G total. ~24kbps Opus / 60s max →
~180 KB per message. 100 msgs/day → 18 MB/day → 7 GB/year. Безопасный budget.

**Eviction policy**: NONE в MVP. Sergey ручной cleanup когда понадобится.
Ponytail: добавим find-mtime-cron когда disk usage станет проблемой, не раньше.

## SP4 — Bot identity env vars ✅

`VKConfig.fromEnvironment` уже читает:
- `VK_BOT_TOKEN` (required)
- `VK_BOT_GROUP_ID` (Int, required)
- `VK_BOT_OWNER_IDS` (CSV → Set<Int>, allowlist, required, non-empty)
- `VK_API_VERSION` (default "5.199")

Совпадает со spec. **Action для Sergey**:
1. Создать community access token (scope: messages + docs) — UI VK.
2. Найти `group_id` и свой `user_id`.
3. Добавить в `/etc/voice-backend.env`:
   ```
   VK_BOT_ENABLED=true
   VK_BOT_TOKEN=<...>
   VK_BOT_GROUP_ID=<...>
   VK_BOT_OWNER_IDS=<sergey_user_id>
   VOICE_AUDIO_STORAGE=/var/lib/voice-bot/raw
   VOICE_AUDIT_LOG=/var/lib/voice-bot/audit.jsonl
   ```
4. `chmod 600` уже стоит.

`VK_BOT_ENABLED=true` — новый bool gate (если false → backend не стартует VK
loop, остаётся только `/v1/voice/intent` HTTP endpoint). Добавлю в Composition.

## SP5 — Happy target_cwd ⚠️ ACTION REQUIRED

`/root/.happy/sessions.json` сейчас: **NO running session for `/root/projects/cashflow`**.

Running sessions:
- `/root/projects/voice` (мы)
- `/root/projects/assistant`
- `/root/projects/agentops`
- `/root/projects/avito-aider-claude-cli`

**Action для Sergey**: запустить Happy сессию в `/root/projects/cashflow` до
MVP go-live. Иначе scenario S-4 (Happy session not running) будет каждый раз.

Альтернатива — выбрать другую target_cwd. `/root/projects/assistant` — твой
основной dispatcher, может быть лучше как воронка для voice.

## Существующий VK код — состояние

✅ `VKModels` (full)
✅ `VKAPIClient.getLongPollServer + sendMessage` (text)
✅ `VKLongPollClient` (actor, failed:1/2/3/4)
✅ `VKEventParser` (.text / .voice / .ignored outcomes)
✅ `VKConfig.fromEnvironment` (env + allowlist)
✅ 35/35 XCTest зелёные

❌ `VKHTTPClient.download(url:)` — GET link_ogg без auth headers (link уже
   self-authenticated через token в query).
❌ `VoiceMessagePipeline` — orchestrator (NEW).
❌ `AudioStorage` — .ogg writer + audit.jsonl append (NEW).
❌ `TranscriptDecider` — vk_transcript vs Whisper picker (NEW, ~10 LOC).
❌ Integration в main.swift — wire VKConfig + run loop + pipeline.

## Готов к Phase 2 TDD ladder

Все mock boundaries у нас есть: `VKHTTPClient` (MockVKHTTPClient уже в tests),
`LiveHappyInjectMessenger` (можно заменить closure replyProvider для тестов),
`WhisperHTTPRelay` (HTTPClient injectable).

**Open для Sergey:**
1. Approve target_cwd: cashflow (создай сессию) или assistant (твой dispatcher).
2. Когда credentials VK готовы — добавь в `/etc/voice-backend.env`.
3. После — TDD ladder начинаю с RED E2E `VoiceMessagePipelineE2ETests.swift`
   (8 сценариев из spec).
