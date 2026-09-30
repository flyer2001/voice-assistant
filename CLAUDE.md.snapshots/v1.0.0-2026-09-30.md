---
version: 1.0.0
bumped: 2026-07-21
---

# Voice project — правила сессии

Проектная сессия. **Не диспетчер**, не закрывать чужие задачи.

## Контекст

- [VISION.md](VISION.md) — что строим и зачем
- [MVP.md](MVP.md) — scope первой итерации и DoD
- `.claude/TASKS.md` — текущие задачи (создать после старта)
- `.claude/CHANGELOG.md` — история сессий (prepend через `/endsession`)

## Стек

- **Swift / SwiftUI** — клиенты (iOS + macOS), shared target где возможно
- **WhisperKit** — on-device STT (https://github.com/argmaxinc/WhisperKit)
- **AVFoundation** — audio capture
- **Hummingbird 2** — backend на VDS, отдельный systemd unit
- **GRDB.swift** — если потребуется персист на клиенте (v0.3+)

## Принципы (помимо общих из ~/projects/assistant/CLAUDE.md)

- **On-device first.** Аудио не уходит в сеть. STT локально.
- **Кроссплатформенность через shared SwiftUI.** Не пилим два независимых UI.
- **MVP в одном клиенте.** Стартуем с одной платформы (iOS ИЛИ macOS),
  cross-platform — v0.2 после E2E работает.
- **Backend минимальный.** Hummingbird endpoint без БД в v0.1, JSONL-лог
  для observability достаточно.

## Что НЕ делаем сейчас

- Wake-word, always-on listening
- Сторонние STT (OpenAI, Whisper API, Deepgram)
- TTS reply (v0.4 если вообще)
- Real-time voice диалог (это не Siri)

## Workflow

Стандартный: TASKS.md → работа → /endsession close|continue → CHANGELOG
prepend → коммит doc-апдейтов.

## TDD-дисциплина

Первое что нужно сделать в этой сессии **до старта v0.0**: ресёрч и сборка
TDD-strategy для voice. Это не «писать тесты по факту», а структурный
подход.

Эталон — **cashflow**. Там проделана большая работа:
- `/root/projects/cashflow/.claude/TESTING.md` (442 строки) — главное чтиво.
  Anti-cementing rules, контракт vs деталь хранения, TPP ladder,
  Builder pattern для тестов.
- `/root/projects/cashflow/.claude/CLAUDE.md` — связанные правила.
- Последние git'овые улучшения (см. recap сессии cashflow 2026-06-06):
  тесты переписаны через TPP-incremental, comments на JSONL-цементы
  как enforcement правила.

Прочитай `cashflow/.claude/TESTING.md` целиком, выпиши что применимо к
voice (Swift, iOS+macOS, network mocking) и что не применимо. Не копируй
дословно — voice свой stack, нужна адаптация.

Параллельно — **запусти Explore-subagent** по `/root/projects/myRep/_project-hub/`
с запросом «гипотезы и заметки про TDD, testing strategy, anti-cementing,
TPP, contract vs implementation». Цель: найти ещё гипотезы Sergey'я,
которые можно прокатить в voice сразу.

Результат — отдельный `.claude/TESTING.md` в voice (адаптация cashflow +
гипотезы из hub'а), до старта первого теста v0.0.

## Связь с другими проектами

- Использует Happy inject протокол (~/projects/assistant/scripts/inject/inject.mjs)
- Может звать sessions-db MCP для классификации
- Reverse-туннель к mac-work НЕ нужен (это не secrets-flow)
