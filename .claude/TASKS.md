# TASKS — voice

> Active sprint. Done — `[x]`, blocked — `[!]`, in-progress — `[~]`.
> История сессий — в `.claude/CHANGELOG.md` (prepend через `/endsession`).

## v0.0 — DONE

- [x] Memory bootstrap (5 файлов: decisions, sellability, TDD sources, inject ref, user workflow)
- [x] `.claude/TESTING.md` — TDD strategy (cashflow adaptation + HYP-036/043/010/004/030)
- [x] `LICENSE` placeholder (proprietary)
- [x] `.gitignore` (Swift/SPM/Xcode/secrets/WhisperKit models)
- [x] `secrets.example` (BACKEND_URL/TOKEN, CLIENT_ID, dispatcher-specific vars в отдельной секции)
- [x] `Package.swift` (iOS 17 primary / macOS 14, VoiceAssistant library + VoiceAssistantTests target)
- [x] `Sources/VoiceAssistant/Backend/BackendAdapter.swift` — protocol, TranscribedRequest, Reply, BackendError
- [x] `Sources/VoiceAssistant/Backend/DispatcherAdapter.swift` — skeleton (throws backendUnavailable, реализуется в v0.1)
- [x] `Tests/VoiceAssistantTests/PackageSanityTests.swift` — protocol reachable + Reply equality
- [x] `specs/backend-protocol.md` — wire contract, self-contained
- [x] `README.md` обновлён (adapter pattern, dispatcher как один из многих)
- [x] `scripts/setup-mac-home.sh` — brew + node + XcodeBuildMCP install (idempotent)
- [x] `docs/mac-home-setup.md` — workflow split (client mac-home / backend VDS), MCP config snippet
- [x] git init + initial commits (`ccf571b` foundation, `20a2ebc` TASKS.md, `873b450` rename + mac-home setup)
- [x] push в `flyer2001/voice-assistant` private (origin set, main -> main, 2026-06-07)

### v0.0 mac-home prep — DONE 2026-06-08

- [x] Xcode 26.0.1 + iOS 26.0/18.5 simulators (license accepted, all platforms)
- [x] DEVELOPER_DIR в `~/.zshrc:11` (per-user без sudo)
- [x] Repo cloned: `~/projects/voice-assistant/`
- [x] Toolchain: brew 5.1.11, node 24.10.0, npm 11.6.2, gh 2.83.0, git 2.39.5, Claude Code 2.1.144
- [x] XcodeBuildMCP 2.6.2 installed (через VDS proxy — direct registry заблокирован ISP)
- [x] MCP `xcodebuild` в `~/.claude.json` — args `["mcp"]` (без него v2.6+ не стартует)
- [x] Network workaround: `claude-ufo` alias (WG 10.10.0.1:8388) + `~/.npmrc` proxy + SSH ProxyJump для github.com
- [x] `claude-ufo /login` выполнен пользователем
- [x] E2E verify: `swift build` 31.89s, `swift test` 2/2 ✓, `xcodebuildmcp mcp` server initialized

### v0.1 client mac-home onboarding (TODO для следующей mac-home сессии)

- [ ] First mac-home Claude session — seed reading: README.md → CLAUDE.md → docs/mac-home-setup.md → .claude/TESTING.md → .claude/TASKS.md → MEMORY.md
- [ ] Spike: попросить mac-home Claude — `claude mcp list` (зависал у меня через SSH non-interactive, в реальной session должно работать). Verify xcodebuild + cupertino MCPs available
- [ ] Spike: build empty iOS app target из Xcode через XcodeBuildMCP, verify simulator boots + screenshot работает

---

## v0.1 PRE-REQ: Whisper location decision

**Deferred 2026-06-07** — решается после бенчмарка. Влияет на specs/backend-protocol.md и client wire-format.

- [ ] **W1**: Benchmark Whisper модели on-device (M-series Mac, iPhone) — `base` / `small` / `large-v3-turbo`. Метрики: latency на 5с/15с RU+EN, WER на known transcript.
- [ ] **W2**: Benchmark Whisper модели server-side на win-home + mac-home (Whisper.cpp или MLX). Те же образцы, метрики + network overhead.
- [ ] **W3**: Решение: on-device (VISION default) vs server-side. Если server-side — добавить `/v1/voice/audio` endpoint в specs (additive, не ломает v1).
- [ ] **G0 (related)**: Gemini LLM role — отложено пока v0.1 не запущен. v0.3 candidate (intent classifier) ИЛИ post-STT rewrite. Решение не блокирует v0.1.

---

## v0.1 — E2E (DoD: capture→reply ≤ 4с)

**Platform target:** iOS app, dev-run через "My Mac (Designed for iPad)" на mac-home + iOS simulator. Реальный iPhone для UX-валидации.

### Backend (VDS, отдельный Hummingbird service)

- [ ] **B1**: Создать `backend/voice-service/` — отдельный Swift package с Hummingbird 2 dep. `Package.swift` + `Sources/VoiceService/`.
- [ ] **B2**: Endpoint `POST /v1/voice/intent` — accept body (см. spec), валидация, mapping в reply struct. **TDD:** failing test ДО реализации (acceptance criteria: HTTP 200 с правильным JSON shape).
- [ ] **B3**: Auth middleware — Bearer token из header, mismatch → 401 (JSON shape per spec).
- [ ] **B4**: Forward в Happy inject — Swift port `inject.mjs` логики (AES-256-GCM, маппинг cwd → Happy sid). **Research-first:** прочитать `~/projects/assistant/scripts/inject/inject.mjs`, написать failing test на mock-inject endpoint ДО port'а.
- [ ] **B5**: Reply path — wait for assistant message (port `--wait-reply` логики, polling JSONL latest mtime). Timeout 15с (per spec).
- [ ] **B6**: Логирование `/var/log/voice.jsonl` (ts, client_id, text, reply, latency, error). **TDD:** контракт лога — это observability обязательство, тестировать формат.
- [ ] **B7**: systemd unit `voice-backend.service` — отдельный, не цепляется к cashflow-bot. Restart=on-failure, journal logs.
- [ ] **B8**: Deploy на VDS — порт 8089, доступен через WireGuard (внутренний IP), public HTTPS — fallback (nginx reverse proxy).

### Client (iOS app, dev-tested on Mac)

> Все C-тикеты блокированы пока на mac-home нет Xcode + XcodeBuildMCP (см. v0.0 mac-home prep).

- [ ] **C1**: Xcode project `iOS/VoiceAssistant.xcodeproj` — iOS app target. SPM package `VoiceAssistant` подключён как local dep. Info.plist + `NSMicrophoneUsageDescription`.
- [ ] **C2**: Main view skeleton — hold-to-speak full-screen button (SwiftUI). Press-and-hold gesture, visual feedback (waveform mock или просто colored state).
- [ ] **C3**: Mac run target — "My Mac (Designed for iPad)" работает, hold-to-speak by mouse-down/mouse-up. Verify сборка собирается через XcodeBuildMCP.
- [ ] **C4**: AVFoundation audio capture — `AVAudioEngine` + tap on inputNode, append в buffer пока gesture held, stop on release. **Research-first:** sample rate, format (Float32 mono 16kHz для Whisper), microphone permission flow на macOS Tahoe (15+) / iOS 17+.
- [ ] **C5**: STT integration. **Зависит от W3 decision.** On-device → WhisperKit `base` модель load on launch (background). Server-side → upload audio multipart к новому endpoint. **Research-first:** WhisperKit API surface ИЛИ multipart upload + retry semantics.
- [ ] **C6**: DispatcherAdapter — реальная реализация `send(_:)`. URLSession POST, парсинг response per spec, маппинг error codes в `BackendError`. **TDD:** URLProtocol mock, тестируем все error paths.
- [ ] **C7**: Bubble UI — список последних 10 turn'ов (in-memory), text-only, scroll, auto-focus last.
- [ ] **C8**: Keychain storage для `BACKEND_TOKEN` — first-launch onboarding (prompt → write). **TDD:** Keychain abstraction `protocol TokenStore` + `KeychainTokenStore` + `InMemoryTokenStore` для тестов.
- [ ] **C9**: Конфигурация через `secrets.local` (read at launch на Mac dev, override Keychain если файл есть — для dev convenience). На iPhone — только Keychain.

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
