# TDD-стратегия — voice

> Адаптация cashflow/.claude/TESTING.md + гипотезы из myRep/_project-hub
> (HYP-036, HYP-043, HYP-010, HYP-004, HYP-030) под voice стэк:
> Swift / SwiftUI shared, WhisperKit on-device, AVFoundation, Hummingbird 2
> backend. **2026-06-07.**

---

## ⚠️ Критичные правила

1. **TDD обязателен для backend и core-логики клиента** (BackendAdapter,
   intent classification, transcript reducer). **НЕ обязателен** для UI-shell
   (SwiftUI views без бизнес-логики) — там snapshot/screenshot тесты по
   мере появления регрессий.
2. **Swift Testing** (`import Testing`) для всех новых тестов. XCTest
   только если конкретный test-only API недоступен в Swift Testing.
3. **`swift test` без pipe head/tail/grep** — SIGPIPE. Правильно:
   `swift test 2>&1 | tee /tmp/test.log`.
4. **Async без `Task.sleep` в тестах** — clock mock или `withCheckedContinuation`.
   `Task.sleep` в тесте = детонатор флаков.
5. **🔴 Mock только boundaries.** Что мокаем: `URLProtocol` (HTTP), WhisperKit
   model load, AVAudioEngine, file system. Что НЕ мокаем: BackendAdapter
   реализация (если она нужна в тесте — пиши Fake, не Mock), внутренние
   actors.
6. **🔴 Research-first для WhisperKit / AVFoundation API** — WebFetch/Perplexity
   docs + failing test ДО реализации. Apple framework semantics часто
   неочевидны (формат буферов, lifecycle session category, AVAudioEngine
   restart после route change).

```bash
✅ swift test 2>&1 | tee /tmp/test.log
✅ swift test --filter BackendAdapterTests 2>&1
✅ swift test --filter BackendAdapterTests.testSendReturnsReply 2>&1
```

---

## Уровни тестирования

| Уровень | Что | Mock | Пример |
|---------|-----|------|--------|
| **E2E** | User story | MockHTTPServer + FakeWhisperModel | «hold→speak→release → bubble показал reply» |
| **Component** | Один модуль с реальными deps | URLProtocol mock | «DispatcherAdapter преобразует Reply из HTTP 200» |
| **Unit** | Чистая функция / actor / struct | Нет | «TranscriptStore.append поддерживает FIFO=10» |

```
Новая user story?         → E2E (1) + Component (несколько)
Часть existing story?     → Component
Чистая логика?            → Unit
```

### Правила мокирования (voice-specific)

| Что | Правильно ✅ | Неправильно ❌ |
|-----|-------------|----------------|
| HTTP | `URLProtocol` подмена в `URLSessionConfiguration` | MockBackendAdapter |
| WhisperKit | `protocol Transcriber { ... }`, `FakeTranscriber` отдаёт пред-записанный текст | mock внутренний WhisperKit pipeline |
| AVAudioEngine | `protocol AudioCaptureSource { stream() -> AsyncStream<Buffer> }`, `FakeAudioSource` | mock AVAudioEngine методы |
| Filesystem | `protocol TranscriptLog { append(...) }` + `InMemoryTranscriptLog` | mock `FileManager` |
| Clock (timeouts, латентность) | `protocol Clock`, `FakeClock` с ручным advance | `Task.sleep` + tolerance |

**Принцип:** ввести `protocol` границу один раз для тех boundaries, что
реально мокаются. Не плодить protocol'ы под каждый класс.

---

## TDD Workflow (Outside-In)

```
1. User story (MVP §v0.1 пункт)
2. Acceptance criteria (executable: «нажал hotkey, сказал X, в bubble Y»)
3. E2E test FAILING — описывает user-visible поведение
4. Спускаемся: component тест FAILING на конкретном слое
5. Спускаемся: unit FAILING → minimal implementation → GREEN
6. Подъём: component GREEN → E2E GREEN
7. Refactor (тесты остаются зелёными)
```

### Анти-паттерны

❌ Сначала код, потом тест (тест дублирует код)
❌ Mock внутренней логики (Adapter, Store, Reducer)
❌ Тест без assertion: `_ = try await session.send(...)`
❌ `Task.sleep(for: .seconds(1))` в тесте (флак-генератор)
❌ Тестировать SwiftUI ViewBuilder напрямую (`Body.body` — implementation detail).
   Тесть Bindable / ObservableObject state машину отдельно.

---

## Техники TDD

### Triangulation (Beck)

Empty → Single → Multiple — каждый тест ЗАСТАВЛЯЕТ обобщить.

**voice примеры (целевые):**

- `TranscriptStore`: `emptyStore` → `singleEntry` → `tenEntriesFIFO` →
  `eleventhDropsFirst`. Каждый шаг добавляет структурное ограничение.
- `BackendAdapter` retry: `singleSuccess` → `retryOnce` → `giveUpAfterN`.

❌ НЕ triangulation: `send("foo")` / `send("bar")` / `send("baz")` —
варианты одной структуры.

### TPP (Martin) — Transformation Priority Premise

В GREEN-фазе минимальная трансформация:

```
{} → nil → const → variable → statements → if → scalar → array →
container → recursion → function → assignment
```

**voice применение:** для STT/streaming пайплайна не пиши сразу
буферизацию — пиши `return ""` на пустой stream, потом `return frames[0]`
на single, цикл вытащит следующий тест.

### Test Data Builders (Pryce)

Применять когда: 3+ повторов или 3+ properties или setup ≥5 строк.

**voice кандидаты (закладываем сразу):**

- `BackendReplyBuilder` — text, latencyMs, optional error
- `TranscriptionResultBuilder` — text, confidence, language, segments
- `HTTPResponseBuilder` для URLProtocol mock — статус, headers, body, delay

**НЕ Builder:** factory-функция `makeTestReply()` без overrides — это
proto-builder, OK пока вариация одна.

---

## Anti-cementing (voice контекст)

Цель: тест должен **падать когда меняется поведение**, не **падать когда
меняется имя переменной**.

### voice-specific опасности

⚠️ **Цементирование формата сериализации** на wire:
- Backend `POST /v1/voice/intent` body shape — это **контракт**. Тест
  «JSON содержит ключ `text`» — намеренный цемент, помечается комментарием.
- А вот `TranscriptStore.entries[0].rawWhisperOutput.timestamps[0].start`
  — implementation detail. Тестируй observable: `.transcribe(audio:)`
  возвращает что нужно.

⚠️ **Цементирование внутренней структуры аудио-буфера**:
- `AudioBuffer.frameCapacity == 1024` — implementation detail. Цемент
  ловит только когда кто-то решил «возьму другой sample rate». Тест:
  `transcribe(buffer) returns non-empty text`.

⚠️ **WhisperKit модель-специфичные ожидания** — НЕ цементировать. Тест
не должен ждать конкретные слова от `base` модели. Тест должен ждать
«любой непустой transcript при подаче валидного аудио», либо использовать
**FakeTranscriber** с пред-заданным выходом.

### Что цементируем НАМЕРЕННО

- **Wire protocol** клиент↔backend (см. `specs/backend-protocol.md`).
  Тесты `BackendProtocolTests` сериализуют/десериализуют против фикстур
  JSON. Если меняем shape — все клиенты ломаются, должны увидеть.
- **JSONL формат backend-лога** `/var/log/voice.jsonl` — контракт для
  observability (grafana/jq парсят). Цемент намеренный, помечается.
- **Adapter protocol** signature (`BackendAdapter.send(text:) async throws -> Reply`).
  Менять — означает менять все Adapter'ы (Dispatcher, Slack, Raw).

### Правило для AI-агента (включая меня)

При написании теста:
1. Это поле/формат — **контракт** (кто-то снаружи на нём полагается) или
   **деталь хранения**? Контракт → цементируй, **пометь комментарием**.
   Деталь → ищи behavior-уровень.
2. Если переименовать — какие сценарии переосмыслятся? Никакие →
   тест слишком близко к коду. Поменяется семантика → норм, карта
   последствий.
3. Тест дёргает `@testable internal`? Есть публичный метод? → используй
   публичный.

### Goodhart's Law для AI-generated тестов (HYP-036)

Когда AI пишет одновременно код и тест, оптимизация смещается на «тест
зелёный», а не «поведение корректное». Sentinel: если тест читает
`@testable internal` поле, которое сам же AI и добавил — это Goodhart.
Перепиши через публичный API ИЛИ объяви это полем контракта явно.

---

## Research-First для WhisperKit / AVFoundation

**Когда:** новый Apple framework API (AVAudioSession category, AVAudioEngine
node configuration, WhisperKit model loading), новая major-version
WhisperKit.

### 🔴 Чеклист

```
☐ WebFetch/Perplexity Apple docs + WhisperKit README (params + edge cases)
☐ Failing test с edge case (что вернёт API при пустом буфере? при route
  change? при background?)
☐ Live эксперимент в SimpleApp на macOS (если semantics неочевидна:
  audio session interruption, AVAudioEngine restart, microphone
  permission flow)
☐ Только потом реализация
```

**Почему:** Apple framework semantics плохо документированы. AVAudioEngine
после route change (наушники подключены/отключены) часто требует restart
— без research поймаешь в проде.

---

## voice-specific: streaming, audio, async

### Streaming mocks (HYP-004 + HYP-028 sharpening)

`Replay`/HAR (записанные HTTP-фикстуры) подходит для request-response
(`POST /v1/voice/intent`). НЕ подходит для streaming / WebSocket (если
появится в v0.5+ for partial transcripts).

Для streaming:
```swift
protocol BackendStream {
    func send(text: String) -> AsyncStream<PartialReply>
}

struct FakeBackendStream: BackendStream {
    let events: [PartialReply]
    let delays: [Duration]
    // выдаёт events по одному, advance FakeClock между ними
}
```

### Audio timing — детерминизм

Real audio buffering недетерминирован (sample buffering, device-specific
chunking). Тесты НЕ должны зависеть от exact timing.

❌ `#expect(buffer.duration == 1.5)`
✅ `#expect(buffer.duration >= 1.0 && buffer.duration <= 2.0)`
✅ Используй `FakeAudioSource` с pre-recorded buffers — точные значения.

```swift
protocol Clock {
    func now() -> Date
    func sleep(for: Duration) async
}

struct FakeClock: Clock {
    var nowValue: Date
    func advance(by: Duration) { ... }
}
```

### Cross-platform тесты

`Tests/voiceTests/` — backend и core. Запускаем на macOS dev-машине ИЛИ
Linux (если зависит от Foundation only).

`Tests/voiceClientTests/` — UI-слой, AVFoundation, WhisperKit. **Только
macOS executor**. iOS-specific тесты — только на macOS с iOS simulator
target.

**Правило (HYP-043):** если test target тянет `import AVFoundation` или
`import WhisperKit` — он macOS/iOS-only. Backend protocol-уровень должен
быть platform-independent (только Foundation/Hummingbird).

### iOS UI snapshot тесты — anti-pattern alert

Когда snapshot тест на SwiftUI view флакует (animation, Safe Area,
Dynamic Type), соблазн:
- добавить `Task.sleep` перед snapshot
- отключить анимации глобально
- relax assertion (`tolerance: 0.3`)

**Все три — anti-pattern.** Лучше: snapshot НЕ view-render, а state
(`ViewModel.state` через `.dump` strategy из Point-Free Snapshot Testing).

Decision rule: snapshot raw image → когда визуальный регресс критичен
(brand identity). Snapshot state dump → для всего остального.

---

## Doc-drift тесты (паттерн sessions-db)

После того как backend и client targets устаканятся — заводим
`Tests/voiceTests/DocDriftTests.swift`:
- Каждый `.swift` в `Sources/voice/Backend/` упомянут в
  `specs/backend-protocol.md` ИЛИ в `Sources/voice/Backend/README.md`
- BackendAdapter conformances (DispatcherAdapter, FakeAdapter) перечислены
  в `specs/adapters.md`

Не до v0.2 (пока кода мало — overkill).

---

## Шаблон Unit-теста (voice)

```swift
import Testing
@testable import voice

@Suite("BackendAdapter.send")
struct BackendAdapterSendTests {

    @Test("Возвращает Reply при HTTP 200")
    func returnsReplyOn200() async throws {
        let fake = FakeHTTPClient(response: .ok(json: """
            {"reply": "ok", "latency_ms": 42}
            """))
        let adapter = DispatcherAdapter(http: fake, baseURL: URL(string: "https://example.com")!, token: "test")

        let reply = try await adapter.send(text: "hi")

        #expect(reply.text == "ok")
        #expect(reply.latencyMs == 42)
    }
}
```

---

## Шаблон Component-теста (с URLProtocol)

```swift
import Testing
import Foundation
@testable import voice

@Suite("DispatcherAdapter ↔ HTTP")
struct DispatcherAdapterHTTPTests {

    @Test("Отправляет bearer token в Authorization")
    func sendsBearerToken() async throws {
        StubURLProtocol.respond(json: ["reply": "ok", "latency_ms": 1])

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let adapter = DispatcherAdapter(
            session: session,
            baseURL: URL(string: "https://example.com")!,
            token: "secret-token"
        )

        _ = try await adapter.send(text: "hi")

        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization")
                == "Bearer secret-token")
    }
}
```

---

## План внедрения

| Когда | Что |
|-------|-----|
| v0.0 (сейчас) | TESTING.md ✅, скелет `Tests/voiceTests/` создан, **первый failing test на BackendAdapter protocol** перед v0.1 |
| v0.1 | E2E на одном happy-path (capture mock → fake transcribe → adapter → reply). Unit на TranscriptStore, BackendAdapter, error handling |
| v0.2 | UI snapshot (state-dump style) для cross-platform Bubble |
| v0.3 | Intent classification — TDD-стиль критично (regex/keyword tests дешёвые и нужные) |
| v0.5+ | DocDriftTests, streaming mocks если добавим WebSocket |

---

## Канон / литература

- Beck «TDD By Example» (2002)
- Martin «Transformation Priority Premise» (2013)
- Pryce «Test Data Builders» (2007)
- Freeman + Pryce «Growing Object-Oriented Software, Guided by Tests» (2009)
- Cashflow `.claude/TESTING.md` — sibling reference, тот же стэк (Swift Testing)
- HYP-036 (AI-assisted dev risks / SASSI audit) — Goodhart's Law
- HYP-043 (Spec-driven RALPH) — iOS-specific TDD pitfalls
- HYP-010 (Point-Free ecosystem) — Snapshot Testing strategies (dump vs image)
- HYP-004 (Replay/HAR) — HTTP recording для request-response (не streaming)
