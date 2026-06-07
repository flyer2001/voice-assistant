# voice-assistant

Push-to-talk → on-device STT → текст → backend → reply в bubble.

**Не «голосовой ассистент» Siri-style.** Параллельный канал к Happy app
для ситуаций когда руки/глаза заняты (за рулём, на пробежке, между
встречами).

См. [VISION.md](VISION.md) и [MVP.md](MVP.md).

## Структура

- `VISION.md` — что и зачем
- `MVP.md` — scope первой итерации
- `CLAUDE.md` — правила проектной сессии
- `.claude/TESTING.md` — TDD-стратегия (читать ДО первого теста)
- `.claude/TASKS.md` — текущие задачи (создаётся при старте сессии)
- `specs/backend-protocol.md` — wire-контракт клиент↔backend (адаптеро-нейтральный)
- `Sources/VoiceAssistant/Backend/` — Swift package, `BackendAdapter` protocol + реализации
- `scripts/setup-mac-home.sh` — one-shot dev environment setup for mac-home (Homebrew, gh, node, XcodeBuildMCP)
- `docs/mac-home-setup.md` — split клиент (mac-home) / backend (VDS), MCP config snippets
- `iOS/` — SwiftUI client (после v0.1 старта)
- `macOS/` — SwiftUI menu bar app (v0.1 primary, см. MVP)
- `backend/` — Hummingbird 2 endpoint на VDS (отдельный systemd unit)

## Архитектура (кратко)

Клиент — SwiftUI shared (iOS + macOS), AVFoundation для capture, WhisperKit
для on-device STT. Никакого raw audio в сеть.

Backend — pluggable через `protocol BackendAdapter`. В v0.0/v0.1 одна
реализация — `DispatcherAdapter`, форвардит в Claude Code сессии автора
через Happy inject API. Это **личная инфраструктура автора**, не часть
публичного контракта. Любой другой adapter (Slack, raw HTTP, self-hosted
own-server) реализует тот же protocol и работает с тем же клиентом —
см. `specs/backend-protocol.md`.

Если вы клонировали репо и хотите запустить voice без зависимости от
инфры автора — реализуйте свой `BackendAdapter`. Один из планируемых
post-MVP — `RawHTTPAdapter` для self-host'а.

## Сборка

TBD — Package.swift + Xcode project появятся в v0.1.

## Лицензия

[LICENSE](LICENSE) — proprietary placeholder. Финальная лицензия будет
выбрана перед public-share (возможные кандидаты: AGPL-3.0 + commercial
dual, BSL, или permissive open-source).
