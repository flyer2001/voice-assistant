# VISION — voice

**Голосовой канал ввода в dispatcher.** Не «голосовой ассистент» (Siri-style),
а второй канал параллельно с Happy app: вместо тапа в чате — нажал кнопку,
сказал, отпустил → диспетчер получил, обработал, ответил.

## Зачем

- Текстом писать в Happy быстро, но не везде удобно: за рулём, в Moves between
  встречами, на пробежке. Голос закрывает.
- Real-time диалог НЕ нужен. Push-to-talk → текст → роутинг → краткий ответ.
- Цель — не «общаться голосом», а **превратить мысль в action в проекте
  быстрее чем достать iPhone и набрать в Happy**.

## Принципы

1. **Push-to-talk.** Hold-to-speak iOS, global hotkey macOS. Нет always-on
   listening, нет wake-word.
2. **On-device STT.** WhisperKit (Apple-port'd Whisper) на iPhone / M1 Mac.
   Аудио наружу не уходит — privacy + latency.
3. **Текстовый transport.** Транскрипт → POST на VDS endpoint. VDS не ловит
   raw audio, только text.
4. **Кратко обратно.** Reply — текст в bubble. TTS — пост-MVP, не базовое.
5. **Транспорт через WireGuard.** Тот же канал что и iPhone↔VDS уже сейчас.
   Публичный HTTPS — fallback.

## Не делаем

- Голосовой диалог в real-time (см. [[user_voice_workflow_preferences]])
- Wake-word, always-on
- TTS в MVP (опция в v2)
- Сторонние STT сервисы (privacy + dep)

## Sellability constraints

Проект потенциально open-source / sellable. Чтобы это оставалось возможным
без переписывания — соблюдаем границы с первого коммита:

- **Отдельный git репо** (`flyer2001/voice` private пока). Никаких
  файловых import'ов между `assistant.git` и `voice.git`. Обмен только
  через **публичные интерфейсы** (REST contract, протоколы в `specs/`).
- **Backend как pluggable adapter, не hardcoded.** В коде `protocol
  BackendAdapter { func send(text: String) async throws -> Reply }`. В v0.1
  одна реализация `DispatcherAdapter` (мой Happy REST + AES-256-GCM). В
  v0.5+ можно добавить `SlackAdapter`, `RawHTTPAdapter`,
  `OwnServerAdapter` — open-source/sellable версия НЕ требует
  Happy/диспетчера автора.
- **Specs самодостаточны.** `voice/specs/backend-protocol.md` описывает
  что клиент ждёт от любого backend (request/response shapes, error
  modes). Не ссылается на приватные memory автора.
- **Никаких deployment secrets в репо.** VDS IP, WireGuard ключи, Happy
  session_id → `.env` / `secrets.example`. Реальный `secrets.local` —
  в `.gitignore`.
- **Лицензия не MIT с самого начала.** Placeholder «All rights reserved»
  или dual-license, окончательно решается перед первым public-share.
- **Имя для public namespace** — `voice` сейчас (private), brand'овое
  имя выбираем перед public release (`whisperboard`, `voice-dispatch`,
  `holdtotalk` и т.п.).

## Stack (предположение)

- **Client** (iOS + macOS): SwiftUI shared, AVFoundation для capture,
  WhisperKit для STT, URLSession для transport.
- **Backend** (VDS): Hummingbird 2 endpoint `/voice/intent`, форвардит в
  dispatcher через inject API (Happy REST + AES-256-GCM из
  [[reference_happy_inject_protocol]]) или через sessions-db MCP.
- **Auth**: API key в Keychain клиента, WireGuard на транспорт.

## Архитектурный эскиз

```
[iPhone/Mac] ─[hold-to-speak]→ [AVFoundation] → [WhisperKit on-device]
                                                       │
                                                       └→ text
                                                          │
            ┌─────[WireGuard tunnel]──────────────────────┘
            │
            ▼
[VDS Hummingbird 2 /voice/intent]
            │
            ├→ classify intent (heuristic | LLM)
            │
            ├→ [dispatcher inject API] → Claude Code session
            │                                  │
            │                                  └→ assistant reply
            │
            └→ [response] → клиент
                              │
                              ▼
                       [text bubble в client]
```

## Связь с другими проектами

- Использует протокол [[reference_happy_inject_protocol]] (REST + AES-256-GCM)
- Использует tunnel infrastructure VDS (WireGuard, MikroTik)
- Возможно — sessions-db MCP для классификации intent (поиск релевантной сессии)
