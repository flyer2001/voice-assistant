# voice-agent-mac MVP — план (2026-07-13)

**Цель:** живой голосовой ассистент на mac-home с фокусом на проекты + push-нотификации от других Claude сессий (heartbeat). Прототип, потом порт на CoreS3 wearable.

**Repo:** `voice-repo/clients/voice-agent-mac/` (внутри существующего, отдельный не создаём).

**Язык:** Python (для скорости прото + mlx-whisper native). Swift позже если нужно shared types с MCU firmware.

## Stack

- **STT:** mlx-whisper (Apple MLX Metal, mac-home local)
- **LLM:** Claude Fable 5 через Anthropic API
- **TTS:** Yandex SpeechKit `alena` через VDS `voice-reply-tts` wrapper (remote, без key management на mac)
- **Wake word:** Porcupine custom «Алёнка» (free tier)
- **Focus routing:** reuse Phase 6 (`/var/lib/voice-bot/focus.json`)
- **Session notifications:** новый endpoint на voice-backend + polling или SSE

## In scope

- Wake word активация
- Live dialog (chunked streaming TTS ощущается непрерывным)
- Focus target routing (voice → focused Claude session inject)
- Heartbeat / push notifications от других сессий → TTS playback
- Cancel gesture (Escape)
- JSONL logging всех событий

## Out of scope (v0.2+)

- CoreS3 порт (Phase 7)
- BT HFP profile
- Multi-user
- Voice output routing (Bluetooth speaker, etc)
- Advanced VAD tuning

## Что нужно от Sergey перед стартом

- [ ] Anthropic API key (Fable 5) — впиши в `~/.voice-agent-mac/config.json`
- [ ] Porcupine access key + train «Алёнка» keyword (5 мин console.picovoice.ai)
- [ ] Подтвердить: TTS через VDS remote (default) vs local Yandex install
- [ ] SSH-доступ mac-home (для меня, через claude-ufo alias — уже есть)

**НЕ НУЖНО:** OpenAI API key.

## User stories

### US-1: Wake word активация

**Как** Sergey **хочу** сказать «Алёнка» → ассистент начинает слушать.

**AC:**
- Porcupine detects wake → 50-100ms beep feedback → mic capture starts
- False positives < 5% в шумной обстановке (игра)
- Wake latency < 500ms

### US-2: Local Whisper STT

**Как** Sergey **хочу** быстрое распознавание без сети.

**AC:**
- mlx-whisper turbo model, ru language hint
- Audio → transcript в 200-500ms на 3-сек clip
- Fallback: если mlx-whisper упал → POST /v1/voice/audio VDS (ubuntu-home fallback)

### US-3: LLM (Claude Fable 5)

**Как** Sergey **хочу** умный ассистент с context'ом моих проектов.

**AC:**
- Transcript + focus.json context → Anthropic API
- Model: `claude-fable-5` (уточнить model ID при setup)
- Streaming response (server-sent events)
- Anthropic API call ~500-1500ms до первого токена

### US-4: Chunked live TTS playback

**Как** Sergey **хочу** слышать ответ ассистента почти сразу.

**AC:**
- Stream Fable response → бьём на предложения по знакам препинания
- Каждое предложение → POST на VDS `voice-reply-tts` → получаем .ogg → play immediately
- Следующее предложение отправляется параллельно (async pipeline)
- Ощущается как streaming: первое слово через 1-2с, дальше без пауз

### US-5: Focus routing

**Как** Sergey **хочу** переключать target-сессию голосом.

**AC:**
- Reuse Phase 6 `/var/lib/voice-bot/focus.json`
- Voice command «фокус на voice» / «переключись на myRep» → `voice-focus <target>` на mac-home
- Assistant responses идут в focused Claude session через `voice-backend /v1/voice/intent` (Happy inject)
- Focus source из focus.json, mac-home client не хранит

### US-6: Heartbeat / session notifications

**Как** Sergey **хочу** слышать когда другая сессия завершила работу.

**AC:**
- Claude session вызывает MCP tool или bash `voice-notify "текст"` → POST на voice-backend `/v1/voice/notify` (новый endpoint)
- voice-backend хранит queue уведомлений
- mac-home client polls каждые 3-5с (или SSE stream)
- Пришло → TTS playback через Yandex + прерывает текущий диалог (или ждёт паузы)
- Формат: «Сессия <name>: <текст>» — короткое

**Уточнить с Sergey:**
- Что триггерит heartbeat? Явный `voice-notify` вызов из сессии, или auto после каждого response.done?
- Prio для notifications: interrupt текущий диалог или queue?

### US-7: 🔴 JSONL логирование

**Как** Sergey **хочу** все события в JSONL для post-hoc анализа.

**AC:**
- Path: `~/.voice-agent-mac/logs/YYYY-MM-DD.jsonl`
- Обязательные события: wake.detect, stt.start/end, llm.stream_start/token/end, tts.chunk_request/play, focus.switch, notification.received/played, error
- Полный transcript в логе (mac-home local, privacy ok)
- Никогда не логировать: API keys, raw audio bytes

### US-8: Cancel gesture

**Как** Sergey **хочу** отменить запись Escape'ом.

**AC:**
- Global hotkey Escape → drop current recording, no LLM call
- Icon → ❌ 1s → idle
- Log `cancel` event

## TDD подход

Согласно `.claude/TESTING.md`:

- Framework: **pytest** (Python) — не Swift Testing, потому что Python client
- Anti-cementing: тесты на contract, не implementation
- Mock только boundaries: `subprocess` calls (whisper, tts wrapper), `httpx` mocked, filesystem, sounddevice → protocol Fake
- Fake > Mock для внутренних

**Порядок TDD (TPP):**

1. Config loader + tests
2. EventLogger (JSONL append + schema check) + tests
3. WhisperClient (subprocess call `mlx-whisper` → transcript) + tests
4. AnthropicStreamer (stream Claude Fable response by sentence) + tests
5. TTSChunker (sentence → TTS request → audio bytes) + tests
6. AudioPlayer (queue + play chunks) + tests
7. WakeWordListener (Porcupine wrapper protocol) + Fake + tests
8. NotificationPoller (polling voice-backend) + tests
9. HotkeyMonitor (Escape cancel) + Fake + tests
10. AgentLoop (integration с Fake коллабораторами)
11. Real hardware acceptance (manual: реальный wake, реальный диалог)

## Задачи (первая неделя)

- [ ] **T1:** Setup mlx-whisper на mac-home + smoke test (record 5s → transcribe)
- [ ] **T2:** Test Claude Fable 5 API — model ID, streaming, latency
- [ ] **T3:** Voice-backend `/v1/voice/notify` endpoint (POST + queue in-memory)
- [ ] **T4:** `voice-notify <text>` bash wrapper для установки на все проекты через `install-project.sh`
- [ ] **T5:** Rewrite agent.py — Python chain (whisper → Fable → TTS chunker → player)
- [ ] **T6:** Config schema + loader + tests
- [ ] **T7:** EventLogger + tests
- [ ] **T8:** TTSChunker + AudioPlayer + tests
- [ ] **T9:** NotificationPoller + integration
- [ ] **T10:** Wake word + hotkey cancel
- [ ] **T11:** First E2E dogfood: wake → question → answer → повторить 5 раз
- [ ] **T12:** Session notification E2E: другая Claude сессия вызывает voice-notify → услышал в наушниках через 5с

## Cost estimate

- Claude Fable 5 API: ~$3-15/1M tokens (типичный диалог ~200-500 tokens → ~$0.001-0.005 per turn)
- Porcupine: free tier
- mlx-whisper: 0 (local)
- Yandex SpeechKit: ~$0.02/min TTS (уже есть, доп cost 0)

**Total:** ~$0.005 per dialog turn. 100 turns/day = **$0.50/day, $15/month**.

## Open questions

- Отдельный endpoint `/v1/voice/notify` или reuse `/v1/vk/send`?
- Прерывать диалог при notification или ждать паузы?
- Формат notification: «Сессия X: текст» или без префикса?
- Cancel gesture — только Escape или ещё wake-word-doubles?
