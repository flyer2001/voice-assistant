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

## v0.1 PRE-REQ: STT location decision — RESOLVED 2026-06-10

Бенчмарк закрыт. См. `bench/results/REPORT-2026-06-10.md`.

- [x] **W1**: On-device бенч. **iPhone 13 mini iOS 26.5:** Apple DictationTranscriber WER 50% / Term 29% / 1166ms (winner). SFSpeechRecognizer WER 84% (fail). SpeechTranscriber 100% WER (broken — debug отложен). WhisperKit на iPhone — отложен (V2, нужен pre-download через VDS proxy).
- [x] **W2**: Server-side бенч. **Whisper large-v3-turbo на Win-CUDA (RTX 3070): WER 30% / Term 77% / 447ms (RTF 0.03, 33× realtime).** Cross-validation на Mac-Metal даёт identical WER ±2%. Win-CUDA в 3.4× быстрее Mac-Metal.
- [x] **W3**: **Решение — гибрид. Primary: server-side через Win-CUDA Whisper turbo (POST /v1/voice/audio multipart, добавляем в specs/backend-protocol.md v2). Fallback offline: on-device Apple DictationTranscriber + fuzzy intent matcher.** SFSpeechRecognizer не используем (legacy + лимит 15s + 2% term acc).
- [x] **HYP-045** (voice IVR через GSM) bonus result: ΔWER (clean → GSM 06.10) для turbo/dictation = +0.6 — +1.6% 🟢 (threshold был >15%). Voice IVR PoC жив — можно делать.
- [ ] **G0 (related)**: Gemini LLM role — отложено пока v0.1 не запущен. v0.3 candidate (intent classifier) ИЛИ post-STT rewrite. Решение не блокирует v0.1.
- [x] **W4-Gemma**: Gemma 3n E2B audio bench (Win-CUDA) — **выбыл**. WER 44.5% clean / 65.2% GSM (vs Whisper turbo 30/31%), 25.4s/файл (в 57× медленнее). Hardware constraint: model offloaded в CPU 11.7GB RAM (RTX 3070 8GB не вместил). Verbatim STT не годится; возможно интересна для **«статья-заметка»** output style — long-form bench следующая сессия. Writeback в HYP-028.
- [x] **W4-TextNorm**: Numbers normalization production code (`Sources/VoiceAssistant/TextNormalization.swift` + tests). На нашем корпусе zero impact — Whisper/Apple Speech уже выдают digits сами. Оставлен для future cloud STT.
- [ ] **W4-Speech**: SpeechTranscriber debug (iOS 26.5 empty output) — отложено
- [x] **W4-WhisperKit-iOS** (2026-06-11): WhisperKit base на iPhone 13 mini V3 — 96 транскрипций. WER 62.6% / Term 50.7% / 368ms (3× быстрее DictationTranscriber, но WER хуже на 13pp). **Не upgrade** к Apple stack по качеству; win только на latency. Для v0.1 on-device остаётся DictationTranscriber. См. `bench/results/ios-v3-bench-metrics.csv`.
- [x] **W5** (2026-06-11): Long-form bench (28-min EN podcast). Whisper turbo 12.6% WER но wall-of-text (2 sentences). Whisper large 11.4% WER с 213 sentences (article-workable). Gemma 3n 29-sec sample — perfect article style (caps, periods, abstracts URLs), full chunked run impractical на RTX 3070 8GB. **Гипотеза Sergey'я о paraphrasing подтверждена на sample.** Decision для article-style: **Path A** = Whisper large + Claude rewrite. См. `bench/results/REPORT-LONGFORM-2026-06-11.md`.

---

## v0.1 — E2E (DoD: capture→reply ≤ 4с)

**Platform target:** iOS app, dev-run через "My Mac (Designed for iPad)" на mac-home + iOS simulator. Реальный iPhone для UX-валидации.

### Backend (VDS, отдельный Hummingbird service) — DONE 2026-06-11 (commit 393ee7b)

- [x] **B1**: Создан `backend/voice-service/` — Swift package с Hummingbird 2.5+ + swift-crypto 3+.
- [x] **B2**: Endpoint `POST /v1/voice/intent` — TDD: failing test первым, 200 OK с reply+latency_ms.
- [x] **B3**: BearerAuthMiddleware → 401 `{"error":"unauthorized"}` на missing/wrong token.
- [x] **B4**: Happy inject Swift port — HappyState (read access.key + sessions.json, pickRunningSession by cwd) + HappyCrypto (AES-256-GCM bundle [version=0][nonce:12][ct][tag:16]) + HappyAPI (POST /v3/sessions/{sid}/messages).
- [x] **B5**: JsonlWatcher — tail latest *.jsonl in ~/.claude/projects/<encoded-cwd>/, extract assistant text, re-scan latest для cold-start/post-endsession resume, advance baseline после read.
- [x] **B6**: RequestLogger /var/log/voice.jsonl — append-only, success/error paths separate, JSON shape с ts/client_id/text/reply|error/latency_ms.
- [x] **B7**: systemd unit `voice-backend.service` + EnvironmentFile example + deploy/README.md.
- [x] **B8**: Release build (47 MB), smoke test passed: 401 (no auth + wrong token) + 503 (no Happy session) + JSONL log line shape — 3/3.
- [x] **B-tests**: 20/20 unit tests pass (Swift Testing): IntentEndpoint × 3, HappyCrypto × 3, HappyState × 4, JsonlWatcher × 6, RequestLogger × 4.

### Backend extension — VK transport (V-tier, next session)

> Reuse: `tg-client/feature/vk-bot-bridge` спайк (1055 LOC Swift) + RFC v0.6.0 Long Poll migration. См. memory `reference_vk_bot_bridge_spike.md`.
> **DoD V-phase**: voice in (через ВК) → STT → Happy inject → text reply → TTS → voice out (через ВК).

- [ ] **V0**: Cherry-pick `Sources/BotBridge/` infrastructure из tg-client → `backend/voice-service/Sources/VKAdapter/`:
  - VKAPIClient (REST messages.send) + adapt to AsyncHTTPClient (без Hummingbird для Long Poll)
  - VKModels (Codable types) + extend с AudioMessageAttachment + DocsSaveResponse shapes
  - BotSessionState (per-owner state)
  - Battle findings B-02/B-05/B-08/B-09 (см. spike RFC раздел 1.2)
- [ ] **V1**: Long Poll loop — `VKLongPollClient` actor. groups.getLongPollServer + poll {server}?act=a_check&wait=25. Handle failed:1 (ts), failed:2,3 (refetch). TDD: MockHTTPClient.
- [ ] **V2**: Receive — parse `message_new` events. Text → HappyInjectMessenger.send. audio_message attachment → save link_ogg URL для V3.
- [ ] **V3**: Voice STT — download link_ogg → IF VK transcript_state="done" use it ELSE send to Whisper turbo на Win-CUDA (нужен endpoint на win-home, см. V3a). Audit log decision.
- [ ] **V3a**: FastAPI или simple HTTP wrapper на win-home для Whisper turbo — receive WAV bytes → return JSON `{text, latency_ms}`. Минимальный, можно через PowerShell + Python.
- [ ] **V4**: Send text reply — VKAPIClient.messages.send peer_id=<owner_id> message=<text>. Existing API.
- [ ] **V5**: TTS install — Piper TTS на VDS (`~/piper/piper/piper` + voices/ru_RU-irina-medium.onnx + en_US-lessac-medium.onnx). См. memory `reference_tts_piper.md`.
- [ ] **V6**: TTS pipeline — Swift Process wrapping `piper --output_raw | ffmpeg -c:a libopus -b:a 24k -ar 16000 -ac 1 -f ogg`. Streaming pipe. ~2-3 sec total для 100-word reply.
- [ ] **V7**: RU text normalizer ДО TTS — числа `123` → "сто двадцать три", аббревиатуры, dates. `num2words[ru]` (Python script) или Swift regex. Без этого Piper читает "сто двадцать три" как "1 2 3".
- [ ] **V8**: Voice send pipeline — docs.getMessagesUploadServer (type=audio_message, peer_id) → multipart POST file → docs.save → messages.send + attachment=doc{owner_id}_{id}.
- [ ] **V9**: E2E smoke — voice mailbox endpoint в личке VK community. Sergey пишет голос → бот шлёт voice reply + text caption.
- [ ] **V10**: Audit log JSON per request: `{owner_id, peer_id, cmd:"voice_intent", stt_source, stt_ms, inject_ms, tts_ms, total_ms, decision}` → /var/log/voice-vk.jsonl.

### Client (iOS app, dev-tested on Mac)

> C1-C4 закрыты iOS infra-спайком 2026-06-12/13 (commits 1314884 / a94ab30 / f405385).
> C5-C9 закрываются через user-stories S1/S2 (см. STORIES.md), а не в этой секции.

- [x] **C1**: Xcode project `iOS/VoiceAssistant.xcodeproj` (XcodeGen via project.yml) — done 1314884.
- [x] **C2**: Hold-to-speak full-screen button (SwiftUI) — done 1314884.
- [~] **C3**: Mac run target — отложено, sim-only сейчас (iPhone 17 на mac-home Xcode 26).
- [x] **C4**: AVFoundation `AVAudioEngine` capture — done f405385 (LiveAudioCapture protocol + impl).
- [→ S1] **C5**: STT integration server-side — done через story S1 (см. STORIES.md): E1.4 STTUploader, E1.5 ContentView wire.
- [→ S2] **C6**: DispatcherAdapter — будет в story S2.
- [→ S2] **C7**: Bubble UI — будет в story S2.
- [→ S2] **C8**: Keychain TokenStore — S2 E2.5.
- [ ] **C9**: secrets.local (Mac dev override) — backlog.

### S1 (Speech echo) — CLOSED 2026-06-14

> User story see [STORIES.md](STORIES.md). DoD: voice → upload → STT → text on screen.

- [x] **E1.1**: spec POST /v1/voice/audio in specs/backend-protocol.md (3ec85ee).
- [x] **E1.2**: backend mock STT handler — 3 slices: handler + multipart + AudioLimits. 8 tests (5f1291a).
- [x] **E1.3**: real Whisper via FastAPI on win-home — **DONE 2026-06-14**:
  - ✅ FastAPI server (`C:/Users/Serg/whisper-server/server.py`) deployed, CUDA + large-v3-turbo
  - ✅ Backend Swift `WhisperHTTPRelay` on AsyncHTTPClient (Hummingbird-compatible async stack)
  - ✅ `main.swift` STT_MODE=live wires relay through sttProvider closure
  - ✅ E2E loopback: mac-home backend → win-home Whisper → точный RU transcript «Привет,
    тестируем распознавание речи через Виспер.», ~6.8s cold (CUDA warmup), <2s warm
  - Diagnosis: initial URLSession-based relay crashed Swift runtime on macOS 26.4 in
    Hummingbird's async handler context (EXC_BAD_ACCESS in type metadata accessor for
    Application). Spike `hb-spike` reproduced fix with AsyncHTTPClient.shared. Backported.
  - Package.swift bumped to swift-tools 6.0 (was 5.10) — matches current Xcode 26 Swift 6.2.
- [x] **E1.4**: iOS STTUploader (URLSession multipart, typed error mapping, 9 tests via URLProtocol mock) — 57f31df.
- [x] **E1.5**: ContentView wire — capture.stop() → STTUploader.upload → footer renders transcript / typed error (08d94a0).
- [x] **E1.6**: E2E smoke — backend in mock mode on mac-home, curl from VDS via WG returned `[mock] echo 2048 bytes from vds-curl-smoke`, 180ms RTT, server logged 200 OK. iOS sim tap manual-verified by Sergey.

### S2 (Forward to Happy + bubble UI) — in progress

> User story see [STORIES.md](STORIES.md). DoD: transcript → /v1/voice/intent → reply bubble + 10-turn history.

- [x] **E2.1** (2026-06-14): `Turn` value-type (`Sources/VoiceAssistant/Models/Turn.swift`) + `TurnView` SwiftUI render (`Sources/VoiceAssistant/UI/TurnView.swift`). ReplyOutcome enum (.pending/.success(Reply)/.failure(String)). 5 TurnTests green (Triangulation: empty pending → success transition → failure → identity uniqueness → createdAt capture). Full suite 16/16 green on mac-work (mac-home in deep hibernate, pmset sleep 0 still not applied). View not unit-tested per TESTING.md §1.
- [x] **E2.2** (2026-06-14): `TurnsStore` @Observable class (`Sources/VoiceAssistant/Models/TurnsStore.swift`). FIFO with default `maxCount=10`, custom cap via init. `append(_:)` drops oldest on overflow, `updateReply(id:to:)` mutates in place / no-op on missing id. 6 TurnsStoreTests green. Full suite 22/22 green on mac-work.
- [x] **E2.3** (2026-06-14): `DispatcherAdapter` real HTTP impl over URLSession (not AsyncHTTPClient — that crash mode only triggers in Hummingbird async handlers on macOS 26.4, iOS client safe). Wire contract: POST `/v1/voice/intent` with Bearer + JSON `{text, client_id, ts}`. `BackendError` gains `.forbidden` for 403 (spec distinguishes from 401 "check token"). Error matrix: 401 → unauthorized, 403 → forbidden, 429 → rateLimited(retryAfterMs:) (parsed from body), 503 + 500-599 → backendUnavailable, URLError.timedOut → timeout, malformed → malformedResponse. 9 DispatcherAdapterTests + dedicated `DispatcherMockURLProtocol` (sibling suite raced on shared MockURLProtocol). Full suite 31/31 green on mac-home (clamshell-stable now via caffeinate LaunchAgent — see memory `reference_mac_home_clamshell`).
- [ ] **E2.4**: ContentView pipeline — transcript → DispatcherAdapter.send → TurnsStore.append.
- [ ] **E2.5**: Keychain `TokenStore` (BACKEND_TOKEN) + first-launch onboarding prompt.
- [ ] **E2.6**: E2E smoke against real backend (Happy session live).

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
- Hardware-key binding refactor: SwiftUI `.onKeyPress(phases: [.down, .up])` вместо
  текущего `KeyMonitor` (UIViewControllerRepresentable + pressesBegan/Ended). API
  доступен с iOS 17.4 — поднять deployment target, выкинуть ~80 строк UIKit-bridge.
  Текущая реализация (commit a94ab30) работает на iOS 17.0, оставить пока deployment
  target не bumped.
- Background PTT: custom BLE GATT device (ESP32-C3 / nRF52) если потребуется press
  detection вне foreground — ZMK keyboard-mode foreground-only по дизайну iOS.
  См. memory `reference_bt_button_ios_ptt.md`.

---

## Open questions / risks (live)

- Whisper `base` на iPhone 15 — будет ли реально ≤ 600ms? Замерить в v0.2 первой задачей.
- Global hotkey conflicts с другими apps — заложить остroke option (другая комбинация в settings) в v0.1 C3, иначе будет блокер.
- Microphone permission flow на macOS Sequoia (15+) изменился — research-first перед C4.

---

## Operational TODO (post-S1)

- [ ] `voice-service` на mac-home как launchd service (сейчас держится через background ssh который тянется только пока есть claude-сессия). См. `~/Library/LaunchAgents/`.
- [ ] Whisper FastAPI на win-home как Scheduled Task / NSSM (сейчас через WMI Win32_Process Create — переживает ssh disconnect, но не reboot).
- [ ] Sergey: `sudo pmset -a sleep 0 disksleep 0` на mac-home (см. `reference_mac_home_clamshell` memory — иначе SSH/WG отваливаются в clamshell mode).
- [ ] Удалить временные spike-артефакты на mac-home: `/tmp/spike-hb/` (after final review).

## Next stories

- **S2** Forward to Happy + bubble UI — 6 E-тикетов в STORIES.md. Расширяет ContentView, подключает /v1/voice/intent (B-серия backend), bubble UI, Keychain TokenStore.
- **S3** Voice reply via TTS (3-tier Yandex/XTTS/Apple) — 8 E-тикетов в FINAL-CHOICE-TTS-2026-06-14.md. Tier 1 cloud Yandex как primary.
