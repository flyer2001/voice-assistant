# MVP — voice

> Scope первой итерации. Закрытые задачи `[x]`. Подробности по милстоунам — в
> `.claude/CHANGELOG.md` после `/endsession`.

## DoD MVP

End-to-end **push-to-talk → текст → reply** работает в одном клиенте (iOS
ИЛИ macOS, выбираем при старте) с латентностью **≤ 4с от отпускания кнопки
до появления ответа в bubble**.

## v0.0 — Setup (sellability foundation)

Делается ПЕРЕД v0.1. Базовые границы чтобы потом не переписывать.

- [ ] `git init` + `flyer2001/voice` private (через `gh repo create`)
- [ ] `LICENSE` placeholder — «All rights reserved» (НЕ MIT, окончательно
      решаем перед public-share)
- [ ] `.gitignore` для Swift/SPM (DerivedData, .build, *.xcuserstate) +
      `secrets.local`
- [ ] `secrets.example` с placeholder'ами (API_KEY, BACKEND_URL,
      ADAPTER_TYPE), реальный `secrets.local` в gitignore
- [ ] `Sources/voice/Backend/BackendAdapter.swift` —
      `protocol BackendAdapter { func send(text: String) async throws -> Reply }`
      + struct `Reply { text: String; latencyMs: Int }`
- [ ] `Sources/voice/Backend/DispatcherAdapter.swift` — единственная
      реализация в v0.0/v0.1 (Happy REST inject)
- [ ] `specs/backend-protocol.md` — request/response shapes, error modes,
      auth pattern. Самодостаточный, без ссылок на приватную инфру автора
- [ ] `README.md` — явное «один из adapter'ов — личный dispatcher автора,
      другие TODO»
- [ ] Initial commit + push в `flyer2001/voice`

## Скоуп v0.1 (демо, один клиент)

### Платформа на выбор

- [ ] **iOS** — hold-to-speak full-screen кнопка, primary target по UX
- ИЛИ
- [ ] **macOS** — menu bar app с global hotkey (⌘⇧V), быстрее на M1

(Выбираем при старте проектной сессии; второй клиент — v0.2)

### Клиент

- [ ] AVFoundation capture, hold-to-speak UI
- [ ] WhisperKit on-device, модель `tiny` или `base` (тюним после demo)
- [ ] URLSession POST на VDS endpoint
- [ ] Bubble UI с историей последних 10 turn'ов (in-memory, не персист в v0.1)
- [ ] Keychain хранение API key

### Backend (VDS)

- [ ] Hummingbird 2 service на отдельном порту (8089?), systemd unit
- [ ] Endpoint `POST /v1/voice/intent` — accept `{text, ts, client_id}` →
      return `{reply, latency_ms}`
- [ ] Auth: bearer token из header
- [ ] Forward to dispatcher: inject API (Happy REST, см.
      [[reference_happy_inject_protocol]]) или sessions-db MCP `pickup_continue`
- [ ] Логирование `/var/log/voice.jsonl` (ts, client_id, text, reply, latency)

### Transport

- [ ] WireGuard уже работает, проверить что VDS endpoint доступен с iPhone
      через VPN
- [ ] Fallback публичный HTTPS — только если WG нестабилен

## v0.2 (второй клиент)

- [ ] Вторая платформа (если v0.1 был iOS → теперь macOS, и наоборот)
- [ ] Shared SwiftUI компонент Bubble

## v0.3 (intent shortcuts)

- [ ] Заготовленные intents (5-10): «status», «inject в проект X»,
      «напомни», «запиши в myRep», «open project X»
- [ ] Локальная классификация regex/keyword на VDS — не LLM-вызов на каждый
      запрос

## v0.4 (TTS reply)

- [ ] AVSpeechSynthesizer на клиенте
- [ ] Опция в UI: text/voice/both

## v0.5+ (постMVP идеи в backlog)

- iOS Shortcut integration
- macOS Apple Watch companion
- История за день (персист SwiftData)
- Multi-language (текст пока RU/EN автодетект через Whisper, OK)

## Открытые вопросы (надо решить ПЕРЕД проектной сессией)

1. **Repo имя** — `flyer2001/voice` private (default), или brand'овое
   сразу (`whisperboard` / `voice-dispatch` / `holdtotalk` / другое)?
   Решается до `gh repo create` в v0.0.
2. **iOS или macOS первым** для v0.1 demo?
3. **WhisperKit модель** — `tiny` (39M params, ~быстро, RU так-сяк) или
   `base` (74M, лучше RU, +200ms на M1)? Тюним после demo.
4. **Backend reuse**: создавать новый Hummingbird сервис или подмонтировать
   endpoint в существующий cashflow-bot binary?
5. **LICENSE форма** — proprietary «All rights reserved» (default,
   максимальная гибкость), или dual-license с самого начала
   (e.g. AGPL + commercial)? Решается до public-share, не до v0.1.
