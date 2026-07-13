# macOS PTT prototype — MVP spec (P0)

**Phase 7 P0.** Прожить UX голосового PTT-flow до траты денег на MCU-железо.
Одна неделя dogfooding'а на mac-home → решение continue/cancel Phase 7.

## Purpose

Не «идеальный клиент». **Инструмент для UX-исследования**:

- Проверить subjective комфорт hold-to-talk на F19/Karabiner
- Замерить объективную latency PTT→transcript p50/p95
- Обнаружить UX-corner cases до траты 20к на Vostok/CoreS3
- Собрать logging для post-hoc анализа (что тормозит, где ошибки)

## In scope (MVP)

- Global hotkey hold → record → upload → transcript
- Config через `~/.voice-ptt/config.json`
- Menu-bar status icon (4-5 состояний)
- **JSONL logging всех событий** (обязательно, US-6)
- Notification + `say`-playback ответа
- Manual UX metrics по итогам недели (US-7)

## Out of scope (defer, не блокеры)

- Assistant-reply pipeline (echo transcript достаточно)
- Multi-language auto-detect (ru-hint из config)
- Chord gestures (double-click / long-press / hold-tap) — Phase 7 P4
- Silence-timer (pause & resume) — Phase 7 P4
- Cancel gesture — nice to have
- Level meter / volume indicator
- Auto-update / packaging
- Multi-focus routing (VK-forward etc)

---

## User stories

### US-1: Hold-to-talk record

**Как** Sergey, **я хочу** удерживать одну клавишу и говорить,
**чтобы** записать голос без клика мышью.

**AC:**
- Key-down (F19 или config'ed) → recording starts ≤100мс от нажатия
- Key-up → recording stops immediately
- Auto-repeat OS-события не запускают повторный recorder
- Hold <0.3s → игнор ("accidental tap"), лог `ptt.too_short`
- Recording в 16 kHz mono PCM WAV в `$TMPDIR/ptt-<epoch>.wav`

**Anti-cementing:**
- НЕ проверяем внутренний state machine
- Проверяем: (a) recorder.start вызывается, (b) recorder.stop вызывается,
  (c) auto-repeat suppression, (d) too-short cutoff

### US-2: Upload & transcript

**Как** Sergey, **я хочу** увидеть транскрипт после отпускания клавиши,
**чтобы** знать что услышал сервер.

**AC:**
- POST `/v1/voice/audio` с multipart (audio, client_id, ts, lang_hint)
- Bearer auth
- Response 200 → notification "PTT (Nms): <text>"
- Response 4xx/5xx → notification "PTT error: <status>"
- Network timeout 15s → error
- **Retry: НЕТ** (per backend spec — endpoint не idempotent)

**Anti-cementing:**
- Тест на `URLProtocol` mock, не на URLSession internals
- Проверяем request shape (headers, multipart fields), НЕ порядок вызовов

### US-3: TTS-reply feedback

**Как** Sergey, **я хочу** услышать ответ голосом (или увидеть в
уведомлении), **чтобы** не отвлекаться от текущего окна.

**AC:**
- `speakReply=true` в config → `say -v $sayVoice $text`
- Notification показывается всегда (даже если `say` включён)
- `say` fail не блокирует notification и наоборот

### US-4: Status visibility

**Как** Sergey, **я хочу** видеть состояние в menu bar без переключения окон.

**AC:**
- Icons: 🎙️ idle / 🔴 recording / ⏳ uploading / ❓ too-short / ⚠️ error
- Меню содержит "hold F19 to talk" + Quit
- Icon сбрасывается на idle через 1-2 сек после error/too-short

### US-5: Config & permissions bootstrap

**Как** Sergey, **я хочу** понятные ошибки при первом запуске,
**чтобы** не гадать почему не работает.

**AC:**
- Missing `~/.voice-ptt/config.json` → clear stderr + exit 1 + пример пути
- Malformed JSON → clear parse error line
- Mic denied → notification "grant Microphone permission"
- Accessibility denied → notification + link ссылкой на System Settings
- Backend unreachable → error в notification

### US-6: 🔴 Обязательное JSONL логирование

**Как** Sergey, **я хочу** каждое событие PTT-lifecycle в JSONL,
**чтобы** после недели анализировать: где тормозит, какие ошибки, что
менять.

**AC:**
- Path: `~/.voice-ptt/logs/YYYY-MM-DD.jsonl` (день = локальная TZ)
- Append-only, one event per line, UTF-8
- Каждая строка = valid JSON, обязательные ключи: `ts` (ISO-8601 UTC),
  `event`, `session_id` (UUID сессии app), `ptt_id` (UUID одного PTT-цикла)
- События (минимальный набор):

```jsonl
{"ts":"...","session_id":"...","event":"app.start","hotkey":80,"version":"..."}
{"ts":"...","session_id":"...","ptt_id":"...","event":"ptt.down","key":80}
{"ts":"...","session_id":"...","ptt_id":"...","event":"ptt.up","hold_ms":1234}
{"ts":"...","session_id":"...","ptt_id":"...","event":"ptt.too_short","hold_ms":150}
{"ts":"...","session_id":"...","ptt_id":"...","event":"record.start","file":"/tmp/…"}
{"ts":"...","session_id":"...","ptt_id":"...","event":"record.stop","file":"...","size_bytes":32000,"duration_s":1.23}
{"ts":"...","session_id":"...","ptt_id":"...","event":"upload.start","url":"...","size_bytes":32000}
{"ts":"...","session_id":"...","ptt_id":"...","event":"upload.end","http_status":200,"latency_ms":987,"response_bytes":234}
{"ts":"...","session_id":"...","ptt_id":"...","event":"stt.result","text":"...","lang":"ru","stt_ms":412,"stt_engine":"whisper-large-v3-turbo"}
{"ts":"...","session_id":"...","ptt_id":"...","event":"tts.speak","voice":"Yuri","chars":42}
{"ts":"...","session_id":"...","ptt_id":"...","event":"error","phase":"upload","code":"http_500","detail":"..."}
{"ts":"...","session_id":"...","event":"app.stop","reason":"quit"}
```

- Rotation: **нет** для MVP (одна неделя = ~1-2МБ, тривиально)
- **Никогда** не логировать: `backendToken`, полный audio bytes.
  Транскрипт — да (это данные user'а самого, не секрет)

**Anti-cementing:**
- Тесты пишут в temp dir, читают файл, парсят JSON, проверяют события
- Тест на "все обязательные ключи присутствуют" (schema check)
- Порядок вызовов writer.write() НЕ тестируем — только результат в файле

### US-7: UX-метрики недели (manual, не в коде)

**Как** Sergey, **я хочу** структурированный опрос по итогам недели,
**чтобы** решить: заказывать железо или закрыть Phase 7.

Опросник (заполнить руками через `docs/macos-ptt-week-log.md`):

- Latency p50/p95 (через `jq` из JSONL — команду добавить в README)
- Total PTTs за неделю
- False-tap rate (`ptt.too_short` / all)
- Ошибка-rate (upload/error / all)
- Комфортно ли жать F19? (1-5)
- Хочется ли silent-mode (без `say`)? (Y/N)
- Хочется ли chord'ов уже сейчас или голая MVP-кнопка ок? (Y/N)
- Мешает ли задержка? (1-5, где 1=неощутимо, 5=бесит)
- Какие сценарии реально использовал: coding / cooking / walk / driving / other
- Одна вещь которую хочется исправить в первую очередь: ___
- Continue Phase 7? (Y/N + reasoning)

---

## Logging analysis helpers (README examples)

```bash
# p50/p95 upload latency
jq -r 'select(.event=="upload.end") | .latency_ms' \
    ~/.voice-ptt/logs/*.jsonl | \
    datamash percentile:50 1 percentile:95 1

# transcript accuracy — печатаем transcripts для manual review
jq -r 'select(.event=="stt.result") | "\(.ts)\t\(.text)"' \
    ~/.voice-ptt/logs/*.jsonl

# error rate
total=$(jq -r 'select(.event=="ptt.down")' logs/*.jsonl | wc -l)
errors=$(jq -r 'select(.event=="error")' logs/*.jsonl | wc -l)
echo "errors: $errors / $total"

# too-short rate
too_short=$(jq -r 'select(.event=="ptt.too_short")' logs/*.jsonl | wc -l)
echo "too_short: $too_short / $total"
```

---

## TDD strategy

Согласно [`TESTING.md`](../.claude/TESTING.md):

| Модуль | Unit test | Integration | Manual |
|---|---|---|---|
| `Config` | ✓ JSON decoding (happy + malformed + missing fields) | — | — |
| `BackendClient` | ✓ multipart shape через URLProtocol mock | ✓ real backend (opt) | — |
| `EventLogger` (US-6) | ✓ JSON schema + append semantics + concurrent writes | — | — |
| `HotkeyMonitor` | ⚠ CGEventTap unmockable — hoist auto-repeat suppression в Fake-injectable logic | — | ✓ hold F19 |
| `AudioRecorder` | ⚠ AVAudioRecorder unmockable — тест через protocol Fake | — | ✓ реальный mic |
| `AppDelegate` | — | ✓ end-to-end с fake backend + fake logger | ✓ full flow |
| Menu bar UI | — | — | ✓ visual |

**Framework:** Swift Testing (`import Testing`) per TESTING.md rule 2.

**Anti-cementing rules (voice-repo global):**
- Mock только boundaries (URLProtocol, filesystem, AVFoundation via protocol)
- Fake > Mock для внутренних коллабораторов
- Никаких `Task.sleep` — clock protocol если нужен
- Тесты — на **contract** (что кто-то видит извне), не на **implementation**
  (какие internal методы вызвались в каком порядке)

**Порядок TDD (TPP ladder):**

1. Config decode (простейший)
2. EventLogger append + schema
3. BackendClient multipart shape
4. AudioRecorder wrapper через protocol (Fake для теста)
5. HotkeyMonitor logic wrapper через protocol (Fake) — auto-repeat, too-short
6. AppDelegate integration с Fake backend + Fake recorder + Fake logger + Fake hotkey
7. Real hardware acceptance (manual)

Каждый шаг: 🔴 failing test → 🟢 minimum code → 🔵 refactor.

---

## Decisions (2026-07-08)

Решено по ответам Sergey перед стартом:

1. **Backend flow:** STT + forward to `/v1/voice/intent` (полный Happy inject).
   Клиент делает 2 sequential HTTP-вызова: `/v1/voice/audio` → text →
   `/v1/voice/intent` → assistant reply. Обе latency отдельно в JSONL.
2. **Hotkey:** native, без Karabiner. Default = **Right Option** (keycode 61).
   Configurable через config.hotkeyCode для смены.
3. **Log privacy:** полный transcript в JSONL. Это локальный mac, secrets
   не в риске.
4. **Cancel-gesture:** нужен. Escape во время hold = drop record, не
   отправлять. См. US-8.

Открытые (не блокеры):

- Config secrets в plain-JSON (`~/.voice-ptt/config.json`, chmod 600).
  Keychain — nice-to-have если параноить.
- UX-метрики: manual `week-log.md` для MVP, `voice-ptt-report` CLI если
  ручной sync задолбает.

## US-8: Cancel-gesture

**Как** Sergey, **я хочу** отменить запись без отправки, если случайно
или передумал, **чтобы** не засорять backend/логи мусорными обрывками.

**AC:**
- Во время hold hotkey → Escape pressed → **drop current recording**
- Recorder.stop() вызывается, файл удаляется
- НЕ HTTP-запрос
- Log event `ptt.cancel` с hold_ms до Escape
- Icon → ❌ 1 сек → 🎙️
- Если Escape нажат ПОСЛЕ release (когда uploading) — игнорируется

**Anti-cementing:**
- Тест на Fake AudioRecorder: cancel вызывает stop + deleteFile
- Тест на upload не вызывается когда cancel предшествует release

## Deliverables

- [x] `docs/macos-ptt-mvp-spec.md` (этот файл) — 2026-07-08
- [x] `docs/macos-ptt-week-log.md` template опросника — 2026-07-08
- [x] Scaffold `clients/macos-ptt/*` (~350 lines, без TDD) — 2026-07-08
- [ ] **Next session:** Refactor scaffold under TDD:
  - [ ] `Config` + tests (US-5)
  - [ ] `EventLogger` + tests (US-6, JSONL schema)
  - [ ] `BackendClient` + tests (US-2, mock через URLProtocol)
  - [ ] `IntentClient` + tests (US-2 chain — audio→intent)
  - [ ] `AudioRecorder` protocol + Fake + tests (US-1, US-8)
  - [ ] `HotkeyMonitor` protocol + Fake + tests (US-1, US-8)
  - [ ] `AppDelegate` integration test (Fake backend + logger + hotkey)
- [ ] Default hotkey → **Right Option** (keycode 61) в config.example.json
- [ ] Escape monitor для cancel (US-8)
- [ ] README: install + logging jq examples + week-log workflow
- [ ] Build на mac-home + первый живой PTT с JSONL evidence
- [ ] Одна неделя dogfooding, заполнение week-log.md
