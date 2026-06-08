# CHANGELOG — voice

> Prepend новые записи сверху. Никогда не редактировать существующие.

## [2026-06-08] v0.0 sellability foundation + mac-home dev provisioning

**Сделано:**
- ✅ Repo `flyer2001/voice-assistant` создан (private), 5 коммитов запушено: `ccf571b → 20a2ebc → 873b450 → 5991619 → 6f50b26`
- ✅ Sellability foundation: LICENSE proprietary placeholder, .gitignore (Swift/SPM/Xcode/secrets/Whisper models), `secrets.example` с разделением dispatcher-specific vars
- ✅ `Package.swift` (iOS 17 / macOS 14, product `VoiceAssistant`)
- ✅ `Sources/VoiceAssistant/Backend/BackendAdapter.swift` — protocol + `TranscribedRequest` + `Reply` + `BackendError`
- ✅ `Sources/VoiceAssistant/Backend/DispatcherAdapter.swift` — skeleton (throws `backendUnavailable`, реальная реализация в v0.1 C6)
- ✅ `Tests/VoiceAssistantTests/PackageSanityTests.swift` — 2 теста (protocol reachable + Reply equality)
- ✅ `specs/backend-protocol.md` — self-contained wire contract (request/response shapes, error codes 401/403/429/503, auth pattern, timeouts, версионирование v1/v2)
- ✅ `.claude/TESTING.md` — TDD стратегия 350+ строк (адаптация cashflow + HYP-036/043/010/004/030 из myRep hub'а): triangulation, TPP, builders, anti-cementing для voice контекста (audio timing, streaming mocks, iOS snapshot pitfalls)
- ✅ `.claude/TASKS.md` — v0.1 разбит на 24 тикета (B1-B8 backend, C1-C9 client, G1-G3 glue, T1-T4 TDD) + W1-W3 Whisper-decision pre-req + G0 Gemini
- ✅ `scripts/setup-mac-home.sh` — idempotent sanity-checker для базового toolchain'а
- ✅ `docs/mac-home-setup.md` — workflow split (mac-home клиент / VDS backend), proxy chain, MCP config, tripwires
- ✅ **mac-home полностью провижен**: Xcode 26.0.1 + iOS 26/18.5 simulators, brew/node/npm/gh/git, Claude Code 2.1.144, XcodeBuildMCP 2.6.2 (поставлен через VDS proxy, npm registry DNS unreachable напрямую)
- ✅ Сетевой обход: `claude-ufo` alias через WG `10.10.0.1:8388`, `~/.npmrc` permanent proxy, SSH ProxyJump для `github.com` через VDS WG
- ✅ MCP `xcodebuild` в `~/.claude.json` починен: добавлен `mcp` subcommand в args (без него v2.6+ печатает usage и падает)
- ✅ E2E verify на mac-home: `swift build` 31.89s (arm64e-macos14.0), `swift test` 2/2 passed, `xcodebuildmcp mcp` → Server initialized v2.6.2
- ✅ Memory (`~/.claude/projects/-root-projects-voice/memory/`): 7 файлов (decisions, sellability constraints, TDD sources, Happy inject ref, user workflow, dev split, mac-home env, claude-ufo alias)

**Решения:**
- **Platform v0.1: iOS first, dev-run на Mac** (изменено с «macOS first»). iOS app target в Xcode проекте, runs через "My Mac (Designed for iPad)" на Apple Silicon. Финальная цель — iPhone. SPM пакет `VoiceAssistant` как local dep
- **Repo: `voice-assistant`** (изменено с `voice`). Codename, не брендовое имя — переименуется через `gh repo rename` перед public-share. Локальный dir на VDS остался `voice` (cosmetic mismatch, миграция дороже)
- **STT location: DEFERRED.** Раньше планировался `WhisperKit base` on-device. Sergey уточнил — возможна серверная инференс на win-home/mac-home. Решение после бенчмарка (W1-W3). specs/backend-protocol.md устойчив к обоим вариантам (server-side STT будет additive `/v1/voice/audio` endpoint в v2, не breaking)
- **Backend: separate Hummingbird service** на VDS (отдельный systemd unit), не bundle в cashflow-bot binary. Domain decoupling + sellability сохранена
- **Gemini LLM role: deferred** (intent classifier? rewrite? full agent?) — не блокирует v0.1, решим перед v0.3
- **License: placeholder proprietary** до public-share decision (не срочно)
- **Dev split:** клиент на mac-home (Xcode + XcodeBuildMCP), backend на VDS. Single repo, two cwd-keyed memory trees. Coordinate через git commits + cross-linked memory
- **ISP workaround:** весь outbound (claude / npm / git-over-SSH) с mac-home идёт через VDS tinyproxy по WG (`10.10.0.1:8388`). Прямой outbound к github.com:22 и registry.npmjs.org блокируется ISP. Credentials proxy — local-only на mac-home, в репо placeholder'ы

**Открытое:**
- v0.1 PRE-REQ W1/W2/W3: Whisper benchmark (on-device M-series + iPhone, server-side win-home + mac-home) — это решит протокол. Можно начать с серверной части через SSH к mac-home, on-device — задача mac-home Claude сессии
- Backend tickets B1-B8: новый Swift package `backend/voice-service/` с Hummingbird 2, endpoint `/v1/voice/intent`, Happy inject Swift-port (research-first перед B4), systemd unit. Часть зависит от W3 decision
- Client tickets C1-C9: задача mac-home Claude сессии (XcodeBuildMCP теперь готов). Coordination через repo
- Backend session ↔ mac-home session: договориться о zones — этот VDS трогает `backend/`, `specs/backend-protocol.md` (обновления через PR), `Sources/VoiceAssistant/Backend/` (общая зона, читают обе)
- Стейлые happy-coder процессы на VDS (7 вместо 1) — почистить когда удобно, не блокер
- На mac-home `claude mcp list` зависал — проверить причину (возможно сетевой роутинг через proxy блочит discovery), сейчас не критично — MCP работает в session
- Cupertino MCP уже зарегистрирован на mac-home — выяснить что это и нужен ли для voice client

**Файлы:**
- VISION.md (read-only)
- MVP.md (read-only)
- CLAUDE.md (read-only)
- README.md (создал воз структуру)
- LICENSE
- .gitignore
- secrets.example
- Package.swift
- Sources/VoiceAssistant/Backend/BackendAdapter.swift
- Sources/VoiceAssistant/Backend/DispatcherAdapter.swift
- Tests/VoiceAssistantTests/PackageSanityTests.swift
- specs/backend-protocol.md
- .claude/TESTING.md
- .claude/TASKS.md
- scripts/setup-mac-home.sh
- docs/mac-home-setup.md

