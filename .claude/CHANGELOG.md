## [2026-06-14] S1 Speech echo CLOSED end-to-end + win-home Whisper turbo live

**Сделано:**
- ✅ TTS bench финализирован — 5 провайдеров (Apple/Yandex/Piper/Silero/XTTS-v2) × 7 фраз, Sergey оценил MOS, FINAL-CHOICE: Yandex primary (5.0/4.86), XTTS-v2 secondary (3.83/4.5), Apple fallback (2.0/2.83). Audio hosted на VDS, отчёт + SURVEY в `bench/results/`
- ✅ Architecture shift: STORIES.md (S1/S2/S3 + DoD/AC/E-tickets) — переход от spike к story-driven TDD
- ✅ S1 E1.1: spec `POST /v1/voice/audio` в `specs/backend-protocol.md` (multipart + lang_hint + max_duration_s, error matrix 400/401/503/504)
- ✅ S1 E1.2 (3 slices): mock STT handler + multipart parsing (swift-multipart-kit) + AudioLimits (min/max bytes + declared duration). 8/8 backend tests
- ✅ S1 E1.4: iOS STTUploader на URLSession + URLProtocol mock, typed STTUploaderError mapping для всех server errors. 9/9 iOS tests
- ✅ S1 E1.5: ContentView wire — AudioCapture.stop → STTUploader.upload → footer transcript / typed error
- ✅ S1 E1.6 mock smoke: backend на mac-home через STT_MODE=mock, curl VDS→WG→mac-home 180ms RTT, `[mock] echo 2048 bytes from vds-curl-smoke`
- ✅ S1 E1.3 real Whisper: FastAPI на win-home (CUDA + large-v3-turbo), real RU «Привет, тестируем распознавание речи через Виспер» транскрибируется точно. WhisperHTTPRelay в backend (AsyncHTTPClient, не URLSession — diagnosis ниже), E2E loopback green
- ✅ Mac-work pivot tooling: SSHFS mount + `scripts/sim-grant.sh` (TCC pre-grant workaround macOS 26+), build green на iPhone 13 mini OS 18.4

**Решения:**
- **Story+E-ticket terminology**: Story = user-facing описание + DoD + AC. E-ticket = тех. подзадача внутри story (один failing test → один impl). Не путать
- **TTS Tier 1 cloud Yandex / Tier 2 local XTTS / Tier 3 offline Apple**: Yandex ~$0.001/utterance, XTTS multilingual code-mix native (на mac-home/win-home сервере), Apple Milena built-in iOS (fallback без сети)
- **URLSession → AsyncHTTPClient в backend на macOS 26.4**: diagnosed via fresh spike package `hb-spike` — URLSession.shared в Hummingbird async handler context crashes Swift runtime (EXC_BAD_ACCESS в type metadata accessor for Application). AsyncHTTPClient.shared identical pattern: stable. Backport за 5 минут
- **Swift-tools 6.0 + Swift language mode v6**: voice-service Package.swift bumped 5.10 → 6.0
- **Backend dev ⇒ mac-home**: VDS не нагружаем сборкой Swift, только prod deploy + hosting (см. instructions Sergey'я)
- **iOS dev снова на mac-home** (mac-work был временной заменой 2026-06-12); ZMK F15 binding через UIViewControllerRepresentable + pressesBegan/Ended
- **mac-home pmset sleep 0 нужен** — иначе clamshell mode засыпает и SSH/WG отваливаются (pmset memory)

**Открытое:**
- Story S2 (Happy forward + bubble UI): следующая user-facing работа. Transcript из S1 → /v1/voice/intent (existing endpoint) → reply bubble. 6 E-тикетов в STORIES.md
- Story S3 (TTS reply via 3-tier Yandex/XTTS/Apple): E3.1-E3.8 в FINAL-CHOICE-TTS-2026-06-14.md
- iPhone sim tap E2E (real UI) — backend готов в обоих modes (mock + live), Sergey может протестить hold-to-speak руками когда у Mac (manual)
- `voice-service` как launchd service на mac-home для постоянной доступности (сейчас — background ssh holds backend)
- Whisper FastAPI persistent: scheduled task / NSSM на win-home (сейчас — WMI Win32_Process Create, переживает ssh disconnect)
- Sergey не применил `sudo pmset -a sleep 0 disksleep 0` на mac-home — рано или поздно clamshell sleep отрубит connection

**Файлы:**
- backend/voice-service/Package.swift (tools 6.0, +deps multipart-kit/AsyncHTTPClient/NIOFoundationCompat)
- backend/voice-service/Sources/VoiceServiceCore/{Configuration,VoiceServiceApp,STTResult,WhisperHTTPRelay}.swift
- backend/voice-service/Sources/VoiceService/main.swift (STT_MODE=mock/live switch)
- backend/voice-service/Tests/VoiceServiceCoreTests/AudioEndpointTests.swift (8 tests)
- Sources/VoiceAssistant/Backend/STTUploader.swift (new, +tests 9)
- Sources/VoiceAssistant/Audio/AudioCapture.swift (#if os(iOS) wraps AVAudioSession)
- iOS/VoiceAssistant/ContentView.swift (wired STTUploader)
- iOS/VoiceAssistant/KeyMonitor.swift (F15 binding)
- specs/backend-protocol.md (+voice/audio endpoint)
- .claude/STORIES.md (new — S1/S2/S3 + DoD/AC)
- .claude/TASKS.md
- bench/scripts/tts/* (corpus + 5 provider runners + aggregate)
- bench/results/{REPORT,SURVEY,FINAL-CHOICE}-TTS-2026-06-13.md
- Win-home: C:/Users/Serg/whisper-server/server.py (FastAPI Whisper relay)

## [2026-06-11] Backend voice-service v0.1 (B1-B8 GREEN) + iPhone V3 + long-form bench + VK spike found

**Сделано:**
- ✅ **Backend B1-B8 GREEN на VDS** — `backend/voice-service/` Swift package + Hummingbird 2.5 + swift-crypto. POST /v1/voice/intent contract + Bearer auth + Happy inject Swift port (HappyState + HappyCrypto AES-256-GCM + HappyAPI + JsonlWatcher + LiveHappyInjectMessenger composition) + RequestLogger JSONL + systemd unit + deploy README. **20/20 unit tests pass** (Swift Testing) + 3/3 smoke tests pass (401 на missing/wrong token + 503 на отсутствие Happy session + JSONL log shape).
- ✅ **iPhone V3 WhisperKit base bench** — 96 транскрипций через Xcode Run (Sergey разблокировал codesign). WER 62.6% / Term 50.7% / Latency 368ms. **3× быстрее DictationTranscriber** но **WER хуже на 13pp** — не upgrade, trade-off.
- ✅ **Long-form bench (28-min EN Stack Overflow Podcast)** — Whisper turbo + Whisper large на Win-CUDA. Bench script + extended metrics (WER + Term Acc + Readability + Speaker tags + Topic Jaccard). REPORT-LONGFORM-2026-06-11.md с findings.
- ✅ **Gemma 3n 29-sec single-chunk proof** — гипотеза Sergey'я о paraphrasing/article-style подтверждена качественно. Full long-form chunked невозможен на RTX 3070 8GB (44+ min wall-clock без single CSV row).
- ✅ **VK Bot Bridge spike найден** в `tg-client/feature/vk-bot-bridge` (1055 LOC Swift + RFC v0.6.0 Long Poll migration). Battle-tested infra reusable для voice-service V-phase.
- ✅ **Research subagents** (VK Bot API + TTS engines) — 2 параллельных отчёта собрали. Verdict TTS: Piper TTS (ru_RU-irina-medium), MIT license, 22× realtime CPU, fits 4GB VDS.
- ✅ **Memory pointers saved** (3 файла): reference_vk_bot_bridge_spike, reference_vk_bot_contracts, reference_tts_piper. Linked в MEMORY.md.
- ✅ **TASKS.md updated** — B1-B8 marked done с commit hash 393ee7b. V0-V10 (VK transport phase) добавлены с reuse pointer.

**Решения:**
- **Article-style verdict**: Whisper turbo выдаёт wall-of-text (2 sentences / 5637 слов, без punctuation), Whisper large даёт **213 sentences** с avg 26 words/sentence. Для article-style **Whisper large >> turbo** несмотря на 5× slower. Gemma 3n даёт article style natively (caps + punctuation + abstraction), но scaling impractical на consumer GPU. **Production recommendation Path A: Whisper large + Claude API rewrite** (~$0.05 / 28-min file).
- **iPhone V3 WhisperKit base — не upgrade DictationTranscriber'у**: для v0.1 on-device остаётся Apple DictationTranscriber. WhisperKit base — backup option если latency 1166ms критична.
- **VK transport** будет cherry-pick инфраструктуры из tg-client spike, **НЕ полное переписывание**. RFC v0.6.0 раздел 1.5 уже сделал решение webhook → Long Poll (Sergey'ем в мае 2026). Reuse его architecture + B-01..B-09 battle findings.
- **TTS engine: Piper** (vs Silero отбросили из-за CC-BY-NC; XTTS-v2 OOM на 4GB VDS; Coqui shut down 2024). ru_RU-irina-medium MIT, 60-120 MB RAM, streaming via `--output_raw | ffmpeg`.
- **Architecture: один service, два transport** — voice-service на VDS + HTTP /v1/voice/intent (iOS) + Long Poll loop (VK), shared HappyInjectMessenger.

**Открытое:**
- VK creds для следующей сессии: VK_BOT_TOKEN (community, scopes `messages`+`docs`) + VK_BOT_GROUP_ID + VK_BOT_OWNER_IDS — старый VDS с /etc/tg-client.env слетел, нужно новый token Sergey'ю.
- Sergey должен один раз написать боту от user account для opening dialog (canonical VK bot pattern).
- Whisper turbo на win-home — FastAPI wrapper (V3a) для voice-service ↔ win-home access. Sergey выбрал FastAPI вместо SSH-script call. WoL bootstrap (~30s cold start OK).
- Target Happy CWD: /root/projects/voice (recursive, dev-friendly для smoke).
- Bench/results/gemma/* CSVs — untracked dir, gitignored выборочно (raw csv в bench/results/ ignored, в subfolders нет). Не блокер.
- Gemma 3n chunked perf debug — почему single-chunk 24s, chunked loop 44+ min на том же hardware? Возможен memory leak в loop. Backlog.
- num2words[ru] RU text normalizer ДО TTS — без него Piper читает "123" буквально. V7 в плане.

**Файлы:**
- backend/voice-service/{Package.swift, Sources/VoiceService/main.swift, Sources/VoiceServiceCore/*, Tests/VoiceServiceCoreTests/*, deploy/*}
- bench/results/REPORT-LONGFORM-2026-06-11.md
- bench/scripts/{bench_longform.py, compute_longform_metrics.py}
- .claude/TASKS.md (B1-B8 done, V0-V10 added)
- ~/.claude/projects/-root-projects-voice/memory/{reference_vk_bot_bridge_spike.md, reference_vk_bot_contracts.md, reference_tts_piper.md, MEMORY.md updated}


## [2026-06-10/11] STT bench full cycle — Whisper turbo winner + Gemma 3n results + long-form prep

**Сделано:**
- ✅ V1 Apple Speech bench на iPhone 13 mini iOS 26.5 — SFSpeechRecognizer + DictationTranscriber + SpeechTranscriber (V2), 288 transcriptions
- ✅ Win-home + mac-home full Whisper bench — 4 моделей × 32 файла × 3 runs × 2 codecs = 768 transcriptions cross-validation
- ✅ Gemma 3n E2B audio bench (Win-CUDA через HF token) — 96 files clean + 96 gsm = 192 transcriptions
- ✅ Bench scripts (monitor.py + compute_metrics.py + bench_whisper_faster.py + bench_whisper_cpp.py + bench_gemma_hf.py + ffmpeg pipelines)
- ✅ iOS Xcode project setup через XcodeGen — VoiceAssistantApp.xcodeproj, Personal Team signing (`com.voiceassistant.app.flyer2001`), SPM bundle audio resources через `.process(Resources)` + `Bundle.module`
- ✅ TextNormalization (production code) + tests + compute_metrics integration — finding: zero impact на нашем корпусе (Whisper/Apple Speech уже выдают digits сами)
- ✅ HYP-028 + HYP-045 writeback в myRep hub с результатами benchmark
- ✅ TASKS W1/W2/W3 closed
- ✅ Long-form bench prep — Stack Overflow Podcast 28min audio + 5088-word editorial transcript в `assets/long-form-bench/en/`, brief `bench/LONGFORM_BENCH_BRIEF.md`

**Решения:**
- **Server-side STT: Whisper large-v3-turbo на Win-CUDA** (30% WER, 77% Term Acc, 447ms на 15s — 33× realtime). Cross-validation Win/Mac give identical WER ±2pp; Win-CUDA в 3.4× быстрее Mac-Metal на той же модели.
- **On-device STT: Apple DictationTranscriber (iOS 26 new)** на iPhone 13 mini (50% WER, 29% Term Acc, 1166ms). Бесплатно, system-managed, 0 MB app bundle. SFSpeechRecognizer не используется (legacy 15s лимит, 2% Term Acc). SpeechTranscriber broken на iOS 26.5 SDK — отложено в debug.
- **HYP-045 voice IVR через GSM — ✅ FEASIBLE**: ΔWER (clean→GSM 06.10) для Whisper turbo +0.6-1.7% 🟢, Apple DictationTranscriber +1.6% 🟢. Threshold был >15%. Можно делать PoC.
- **Gemma 3n E2B audio — отвергнута для verbatim STT**: WER 44.5% clean (vs Whisper 30%), 65.2% GSM (vs Whisper 31% — катастрофично), 25.4s/файл (в 57× медленнее Whisper). На RTX 3070 8GB не вместилась в VRAM (offloaded в CPU 11.7 GB RAM). Возможно interesting для **end-to-end voice→intent** (где interpretation = feature) или для **«статья-заметка»** output style — это next session.
- **Numbers normalization** — production code сохранён для будущих cloud STT, но не helps на нашем корпусе. Real Set 4 errors — это term split ("WhisperKit"→"Whisper Kit"), не spelled-out digits.

**Открытое:**
- iPhone V3 WhisperKit base прогон — ждём Sergey Run в Xcode утром (Apple stack уже в V2 dataset, WhisperKit small отключен из-за OOM 4GB RAM)
- Long-form bench (Whisper turbo vs Gemma 3n c 30s chunking pipeline) — следующая сессия
- RU long-form candidate — yt-dlp YouTube blocked, retry через mac-home `claude-ufo` proxy в следующей сессии (или искать non-YouTube источник: Habr статьи "по мотивам подкаста", WWDC RU translation, Tinkoff/Avito/Yandex tech talks)
- SpeechTranscriber debug — почему empty в iOS 26.5 (вероятно AssetInventory.assetInstallationRequest silent fail или async lifetime issue)
- В hub'е HYP-028 + HYP-045 writeback дважды коммитился (первый раз 2026-06-10 утром, второй с Gemma 2026-06-11 ночь) — both pushed

**Файлы:**
- bench/scripts/* (5 Python benches + monitor + compute_metrics + 2 ffmpeg shell)
- bench/ground-truth.json (8 transcripts + 31 anglicism + 4 number targets)
- bench/CORPUS.md, bench/IOS_BENCH_BRIEF.md, bench/IPHONE_BENCH_STATUS.md, bench/LONGFORM_BENCH_BRIEF.md
- bench/results/REPORT-2026-06-10.md (final report v3 with Gemma)
- bench/results/all-metrics.csv (1152 rows enriched)
- bench/results/{win,mac,gemma}/*.csv
- Sources/VoiceAssistant/BenchResources.swift (SPM bundle accessor)
- Sources/VoiceAssistant/TextNormalization.swift + Tests/VoiceAssistantTests/TextNormalizationTests.swift
- iOS/* (XcodeGen spec + Swift app + setup-resources.sh)
- docs/whisper-benchmark-plan.md
- .claude/TASKS.md (W1/W2/W3 closed)
- myRep hub: hypotheses/HYP-028, hypotheses/HYP-045 (writeback)
- assets/long-form-bench/en/* (28min audio + 5088-word transcript, gitignored)
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


