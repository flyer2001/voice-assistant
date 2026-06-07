# TASKS — voice

> Active sprint. Done — `[x]`, blocked — `[!]`, in-progress — `[~]`.
> История сессий — в `.claude/CHANGELOG.md` (prepend через `/endsession`).

## v0.0 — DONE

- [x] Memory bootstrap (5 файлов: decisions, sellability, TDD sources, inject ref, user workflow)
- [x] `.claude/TESTING.md` — TDD strategy (cashflow adaptation + HYP-036/043/010/004/030)
- [x] `LICENSE` placeholder (proprietary)
- [x] `.gitignore` (Swift/SPM/Xcode/secrets/WhisperKit models)
- [x] `secrets.example` (BACKEND_URL/TOKEN, CLIENT_ID, dispatcher-specific vars в отдельной секции)
- [x] `Package.swift` skeleton (macOS 14 / iOS 17, voice library + voiceTests target)
- [x] `Sources/voice/Backend/BackendAdapter.swift` — protocol, TranscribedRequest, Reply, BackendError
- [x] `Sources/voice/Backend/DispatcherAdapter.swift` — skeleton (throws backendUnavailable, реализуется в v0.1)
- [x] `Tests/voiceTests/PackageSanityTests.swift` — protocol reachable + Reply equality
- [x] `specs/backend-protocol.md` — wire contract, self-contained
- [x] `README.md` обновлён (adapter pattern, dispatcher как один из многих)
- [x] git init + initial commit `ccf571b`
- [ ] push в `flyer2001/voice` private (waiting — Sergey создаёт репо на github.com, после — `git remote add origin git@github-assistant:flyer2001/voice.git && git push -u origin main`)

---

## v0.1 — E2E на macOS (DoD: capture→reply ≤ 4с)

### Backend (VDS, отдельный Hummingbird service)

- [ ] **B1**: Создать `backend/voice-service/` — отдельный Swift package с Hummingbird 2 dep. `Package.swift` + `Sources/VoiceService/`.
- [ ] **B2**: Endpoint `POST /v1/voice/intent` — accept body (см. spec), валидация, mapping в reply struct. **TDD:** failing test ДО реализации (acceptance criteria: HTTP 200 с правильным JSON shape).
- [ ] **B3**: Auth middleware — Bearer token из header, mismatch → 401 (JSON shape per spec).
- [ ] **B4**: Forward в Happy inject — Swift port `inject.mjs` логики (AES-256-GCM, маппинг cwd → Happy sid). **Research-first:** прочитать `~/projects/assistant/scripts/inject/inject.mjs`, написать failing test на mock-inject endpoint ДО port'а.
- [ ] **B5**: Reply path — wait for assistant message (port `--wait-reply` логики, polling JSONL latest mtime). Timeout 15с (per spec).
- [ ] **B6**: Логирование `/var/log/voice.jsonl` (ts, client_id, text, reply, latency, error). **TDD:** контракт лога — это observability обязательство, тестировать формат.
- [ ] **B7**: systemd unit `voice-backend.service` — отдельный, не цепляется к cashflow-bot. Restart=on-failure, journal logs.
- [ ] **B8**: Deploy на VDS — порт 8089, доступен через WireGuard (внутренний IP), public HTTPS — fallback (nginx reverse proxy).

### Client (macOS menu bar app)

- [ ] **C1**: Xcode project `macOS/VoiceApp.xcodeproj` или SPM-based — определиться (SPM проще для shared логики, Xcode нужен только для bundle/Info.plist/entitlements). Решение в B1/C1 сессии.
- [ ] **C2**: Menu bar app skeleton — NSStatusItem, popover на клик, иконка.
- [ ] **C3**: Global hotkey `⌘⇧V` — hold-to-speak. **Research-first:** SwiftUI vs AppKit для global hotkey (Carbon HotKey API, или MASShortcut, или новый KeyEvent monitor). Failing test на hotkey-config layer.
- [ ] **C4**: AVFoundation audio capture — `AVAudioEngine` + tap on inputNode, append в buffer пока hotkey held, stop on release. **Research-first:** sample rate, format (Float32 mono 16kHz для Whisper), microphone permission flow.
- [ ] **C5**: WhisperKit integration — load `base` model on app launch (background), transcribe buffer on release. **Research-first:** WhisperKit API surface, model download flow, RU language hint.
- [ ] **C6**: DispatcherAdapter — реальная реализация `send(_:)`. URLSession POST, парсинг response per spec, маппинг error codes в `BackendError`. **TDD:** URLProtocol mock, тестируем все error paths.
- [ ] **C7**: Bubble UI — popover content: список последних 10 turn'ов (in-memory), text-only, scroll, auto-focus last.
- [ ] **C8**: Keychain storage для `BACKEND_TOKEN` — first-launch onboarding (prompt → write). **TDD:** Keychain abstraction `protocol TokenStore` + `KeychainTokenStore` + `InMemoryTokenStore` для тестов.
- [ ] **C9**: Конфигурация через `secrets.local` (read at launch, override Keychain если файл есть — для dev convenience).

### Glue / observability

- [ ] **G1**: Latency measurement — клиент логгит `capture_ms + transcribe_ms + network_ms + backend_ms + render_ms`. Цель ≤ 4с total.
- [ ] **G2**: Manual smoke test scenario — записать «status cashflow» → проверить что в `~/.claude/projects/-root-projects-cashflow/<uuid>.jsonl` появилось user-message и reply пришёл в bubble.
- [ ] **G3**: First `/endsession close` — CHANGELOG.md prepend, doc-апдейты, commit.

### Tests (TDD-discipline per `.claude/TESTING.md`)

- [ ] **T1**: Все unit-тесты per TDD-ladder (Triangulation Empty→Single→Multiple для каждого слоя).
- [ ] **T2**: Component тест — DispatcherAdapter ↔ URLProtocol mock — все error paths (401, 429 с retry_after_ms, 503, timeout).
- [ ] **T3**: E2E happy-path с FakeAudioSource + FakeTranscriber + URLProtocol mock backend.
- [ ] **T4**: Latency budget test — fake-end-to-end должен укладываться в синтетическую 1с budget с fake-clock (real budget проверяется в G2 вручную).

---

## v0.2 (запланировано после v0.1 GREEN)

- [ ] iOS client (порт macOS UI логики, hold-to-speak full-screen button)
- [ ] Shared SwiftUI Bubble component
- [ ] UI snapshot тесты state-dump style (Point-Free), НЕ raw image
- [ ] Doc-drift tests (`Tests/voiceTests/DocDriftTests.swift`)

---

## Backlog (post v0.1)

- v0.3 intent shortcuts (regex/keyword classification на VDS)
- v0.4 TTS reply (AVSpeechSynthesizer, opt-in)
- v0.5+ iOS Shortcut integration, Apple Watch companion, история (SwiftData)
- Repo rename: `voice` → бренд (перед public-share)
- License decision: AGPL-3.0 + commercial dual vs BSL vs proprietary

---

## Open questions / risks (live)

- Whisper `base` на iPhone 15 — будет ли реально ≤ 600ms? Замерить в v0.2 первой задачей.
- Global hotkey conflicts с другими apps — заложить остroke option (другая комбинация в settings) в v0.1 C3, иначе будет блокер.
- Microphone permission flow на macOS Sequoia (15+) изменился — research-first перед C4.
