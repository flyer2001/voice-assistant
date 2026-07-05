## [2026-07-05] async callback + TTS + dual channel + Phase 6 C hybrid plan — 3 commits

**Сделано:**
- ✅ **OP1** Whisper FastAPI systemd unit на ubuntu-home (2026-06-23, отдельный commit `89f374c`) — `/etc/whisper.env` + `/etc/systemd/system/whisper.service`, `RequiresMountsFor=/mnt/win-share`, `User=flyer2001`, `Restart=on-failure`. Smoke: 3.12s audio → 674ms STT
- ✅ **MVP.md pivot sync** — переписан под VK бота (Phase 1+2 DONE, Phase 3 hardening, Phase 5 iOS deferred). Устаревший iOS/macOS план из v0.0 убран
- ✅ **Async callback pattern** (commit `3317925`) — sync wait в pipeline упирался в timeout. `LiveHappyInjectMessenger.injectNoWait` (POST без JSONL watcher), `POST /v1/vk/send` endpoint (Bearer auth, `Configuration.vkSendProvider` hook), pipeline ack «👍 принял» вместо ожидания. Dispatcher шлёт reply async через `voice-reply` wrapper (bash, `/etc/voice-backend.env` → 1 call вместо 5-8 tool call'ов на token discovery)
- ✅ **TTS reply** (commit `2d9fac9`) — `voice-reply-tts` bash wrapper. Yandex SpeechKit v1 alena oggopus (~/tmp/*.ogg) → VK docs.getMessagesUploadServer → upload → docs.save → messages.send с `attachment=doc<owner>_<id>`. Total ~3s end-to-end. VK group token re-issued с `docs` scope
- ✅ **Dual channel** (commit `cf987c9`) — `voice-reply-both` wrapper вызывает text+TTS последовательно (text первым чтоб в VK timeline text bubble выше voice bubble). Prefix hint в pipeline обновлён с default=both + требование финального полного текста в chat (Happy app)
- ✅ **Assistant memory** — `reference_voice_reply_protocol.md` в auto-memory с всеми 3 wrappers + when-to-use guidance + ALSO-chat правило
- ✅ **Phase 6 C hybrid спec в TASKS** — F1-F5 tickets (focus.json + routing + commands + global CLAUDE.md + pattern analyzer). Carry-over для новой сессии

**Решения:**
- **Async callback pivot** — sync wait не масштабируется на heavy dispatcher work (msg185 timeout @ 30s boundary, msg179 inject_ms=25s outlier). Fire-and-forget POST + отдельный callback endpoint = решает архитектурно
- **Bash wrappers, не Swift endpoints** — 3 wrappers (voice-reply, voice-reply-tts, voice-reply-both) в `/usr/local/bin` дешевле чем 3 REST endpoints с Config hooks. Только `/v1/vk/send` в Swift (нужно для callback), остальное — bash
- **Dual channel default** (не TTS-only) — Sergey подтвердил preference «везде хорошо» после voice-reply-both. Auto heuristic не строим (сложно на границах), markup Sergey'я работает как opt-out через кириллицу или явную инструкцию в войсе
- **Prefix > memory** для dispatcher hints — memory update alone не сработал (dispatcher следовал inject prefix strict'о). Prefix обновлён параллельно с memory для consistency
- **C hybrid, не B** для multi-project routing — dispatcher остаётся оркестратором (`list_active_sessions`, cross-session inject через inject.mjs), но focus.json позволяет direct routing в проектные sessions когда Sergey markup'ом переключает. Проектные sessions не знают про VK — coupling минимальный
- **Pattern analyzer = on-demand skill, не realtime infra** — audit.jsonl уже пишет transcript_whisper + duration + msg_id, достаточно для post-hoc анализа. Subagent'ом читает audit + dispatcher JSONL за N дней, correlates ±30s window, output в `bench/analytics/voice-patterns-YYYY-MM-DD.md`. Zero prod infra

**Открытое:**
- **Phase 6 C hybrid** (F1-F5) — вся работа в carry-over для новой сессии. ~1.5-2h scope
- **DG1** ad-hoc quality feedback — passive, будет собираться через F5 pattern analyzer автоматом когда F5 готов
- **OP3** assistant Happy keep-running — declared «MVP не нужен», ручной запуск через windows-setup
- **VK Whisper quirk** — латинские аббревиатуры («TTS», «API») читаются криво. Workaround = кириллица если важно
- **Assistant session context** — session running но 96%+ context в старой сессии `f37805f2`. Sergey может compact / open new сам — не блокер voice pipeline

**Файлы:**
- backend/voice-service/Sources/VoiceServiceCore/LiveHappyInjectMessenger.swift (injectNoWait)
- backend/voice-service/Sources/VoiceServiceCore/Configuration.swift (vkSendProvider hook)
- backend/voice-service/Sources/VoiceServiceCore/VoiceServiceApp.swift (POST /v1/vk/send)
- backend/voice-service/Sources/VKAdapter/VoiceMessagePipeline.swift (prefix updates × 3 итерации)
- backend/voice-service/Sources/VoiceService/main.swift (injectNoWait wire + vkSendProvider)
- backend/voice-service/deploy/voice-reply (new bash wrapper)
- backend/voice-service/deploy/voice-reply-tts (new bash wrapper)
- backend/voice-service/deploy/voice-reply-both (new bash wrapper)
- /usr/local/bin/{voice-reply,voice-reply-tts,voice-reply-both} (VDS runtime, не в repo)
- /etc/whisper.env + /etc/systemd/system/whisper.service (ubuntu-home runtime, не в repo)
- /etc/yandex_speechkit.env (VDS runtime, не в repo)
- MVP.md (pivot sync под VK bot)
- .claude/TASKS.md (F1-F5 spec, DG2/DG3 закрыты async'ом)
- .claude/CHANGELOG.md (этот файл)
- /root/.claude/projects/-root-projects-assistant/memory/reference_voice_reply_protocol.md (new + iteration updates)
- /root/.claude/projects/-root-projects-assistant/memory/MEMORY.md (index entry)

## [2026-06-23] MVP_thin² VK voice in / text out — E2E green, 95 tests, 5 commits

**Сделано:**
- ✅ Phase 0 spike (SP1-SP5): VKModels audio_message shape verified, transcript_state async lifecycle → MVP-decision skip, audio storage `/var/lib/voice-bot/{raw/,audit.jsonl}` created on VDS (perms 750/640), VK creds wired via `/etc/vk-bot.env` (EnvironmentFile=- additive), Happy target_cwd switched agentops → assistant (running session)
- ✅ `specs/vk-bot-mvp.md` (179 LOC) — 8 E2E scenarios S-1..S-8 + architecture sketch
- ✅ `specs/vk-bot-mvp-spike-report.md` (122 LOC) — Phase 0 report
- ✅ Phase 2 TDD ladder (lazy variant — impl до tests, mock'и через closures): `TranscriptDecider.swift` (15 LOC, pure func), `AudioStorage.swift` (80 LOC, .ogg + JSONL append), `VoiceMessagePipeline.swift` (170 LOC, orchestrator с DI closures — VKAdapter не depends на VoiceServiceCore)
- ✅ Tests +16: `TranscriptDeciderTests` × 5, `AudioStorageTests` × 3, `VoiceMessagePipelineE2ETests` × 8 (все S-1..S-8 mock'ами). **95/95 backend green** (51 VKAdapter + 44 VoiceServiceCore)
- ✅ main.swift VK loop wire — `VK_BOT_ENABLED=true` → `LiveHappyInjectMessenger` + `WhisperHTTPRelay` + `LiveVKHTTPClient` + `VKAPIClient.sendMessage` bound в pipeline closures, `Task.detached` long-poll forever loop, handles failed:2|3 by refetching getLongPollServer
- ✅ `VOICE_MAX_AUDIO_S` env override (default 300s = VK voice hard cap, был 60)
- ✅ VK Long Poll events enabled via `groups.setLongPollSettings` (message_new + message_reply + message_allow/deny). Prior `message_new=0` блокировало receiving — без любых событий subscription LongPoll просто idle'ит
- ✅ Live smoke E2E green: 5 entries в audit.jsonl, latency p50 7-10s (3s audio → 6.7s, 122s audio → 9.98s, ~12× realtime CUDA Whisper turbo). msg177 62s reject когда был limit 60 → подняли до 300, msg182 122s прошло
- ✅ Operational fixes: ubuntu-home reboot из Windows boot через `bcdedit /set {fwbootmgr} bootsequence` + `shutdown /r`, Whisper launch script fix (shebang + LD_LIBRARY_PATH quoting через heredoc literal), `~/.claude/docs/home-machines.md` banner-detect bug spotted (Windows OpenSSH 9.x теперь generic banner без `for_Windows`)
- ✅ Memory: `feedback_delegate_ios_to_subagent.md` про делегирование iOS-задач subagent'у (после sim Keychain рысканий в B-Happy bind сессии)

**Решения:**
- **MVP scope = voice in / text out** (TTS skip полностью). VK bot transport = zero deployment на клиенте. iOS app откладывается в Phase 2. Sergey'я proposal challenged + урезан в `specs/vk-bot-mvp.md`.
- **`VKAdapter` не depend на `VoiceServiceCore`** — module boundary через closures (DownloadFn, TranscribeFn, HappyInjectFn, VKSendFn). Без protocol'ов с одной impl. Тесты — closures inline.
- **`STT_MODE` / `HAPPY_MODE` независимы** (из прошлой B-Happy bind сессии). `VK_BOT_ENABLED=true` requires оба `live`.
- **Audit JSONL flat filesystem** (без SQLite). `find`/`jq` достаточно на MVP. Eviction NONE — добавим cron когда disk usage станет проблемой.
- **TDD violation признан**: pipeline impl написан до tests. Lazy variant — closures-based DI + clear boundaries (Phase 0 spike) → impl был дешёвый. Tests verified all green с первой прокрутки. В следующий раз — red first.
- **target_cwd = `/root/projects/assistant`** (не cashflow). Cashflow Happy session не была running, assistant — основной dispatcher Sergey'я, естественный target для voice.
- **VOICE_MAX_AUDIO_S=300** (5 min) — VK voice hard cap. Whisper turbo + CUDA RTX 3070 handles на 122s = 3.3s STT (~37× realtime), достаточный headroom для 5 min.

**Открытое:**
- **OP1**: Whisper FastAPI systemd unit на ubuntu-home — сейчас nohup + bash, переживает ssh disconnect но не reboot. Перенесено в TASKS Phase 3.
- **OP3**: assistant Happy session keep-running auto-restart — пока Sergey запускает руками.
- **DG1-3**: Dogfood / variance audit — collect 5+ голосовых разных профилей, проверить edge cases 290/295/305s VK upper bound, корреляция inject_ms vs prompt/output sizes (msg179 27s outlier).
- **VK transcript_state async event** (`audio_message_transcript`) — MVP skip. Перепроверить trade-off если Whisper будет под нагрузкой.
- **macOS Win OpenSSH banner detection broken** — отправил prompt в assistant сессию (создать `bin/detect-home-os.sh` через `uname -s` + `cmd /c ver` fallback + update `~/.claude/docs/home-machines.md`).

**Файлы:**
- backend/voice-service/Sources/VKAdapter/{TranscriptDecider,AudioStorage,VoiceMessagePipeline}.swift (новые)
- backend/voice-service/Sources/VoiceService/main.swift (VK loop wire + VOICE_MAX_AUDIO_S)
- backend/voice-service/Sources/VoiceServiceCore/EnvComposition.swift (из B-Happy bind, commit 4489a30 этой сессии тоже)
- backend/voice-service/Tests/VKAdapterTests/{TranscriptDeciderTests,AudioStorageTests,VoiceMessagePipelineE2ETests}.swift (новые)
- backend/voice-service/Tests/VKAdapterTests/VKAPIClientTests.swift (Swift 6.3 NSLock fix)
- backend/voice-service/Tests/VoiceServiceCoreTests/{AudioEndpointTests,EnvCompositionTests}.swift
- backend/voice-service/deploy/{README.md,voice-backend.env.example} (HAPPY_MODE docs)
- Sources/VoiceAssistant/Audio/AudioCapture.swift (iOS 26 sim crash fix: engine.prepare() перед installTap)
- iOS/VoiceAssistant/ContentView.swift (backendBaseURL 127.0.0.1 → 10.10.0.1)
- bench/results/gemma/gemma-3n-E2B-{clean,gsm}.csv (archived bench artefacts)
- specs/vk-bot-mvp.md, specs/vk-bot-mvp-spike-report.md (новые)
- .claude/TASKS.md, .claude/CHANGELOG.md (этот файл)
- /etc/voice-backend.env + /etc/vk-bot.env + /etc/systemd/system/voice-backend.service (VDS — не в repo, доп. EnvironmentFile=-/etc/vk-bot.env + ReadWritePaths /var/lib/voice-bot)
- /var/lib/voice-bot/raw/ + audit.jsonl (VDS — runtime storage, 5 entries audit, 4 .ogg files)
- Memory: feedback_delegate_ios_to_subagent.md, MEMORY.md index

## [2026-06-18] TASKS.md cleanup — закрытые `[x]` вычищены, контекст в CHANGELOG/specs/bench

**Сделано:**
- ✅ Применил новое глобальное правило `~/.claude/CLAUDE.md` «TASKS.md — только открытые задачи» к проекту voice
- ✅ Подсчёт до: 57 `[x]` closed entries в `.claude/TASKS.md` (219 строк), все sprint summaries `v0.0`, `v0.0 mac-home prep`, `v0.1 PRE-REQ STT decision`, `B1-B8`, `B-Happy-bind`, `S1`, `S2 E2.1-E2.6`
- ✅ Прошёл `CHANGELOG.md` (228 строк, 4 entries: 2026-06-08 v0.0, 2026-06-10/11 STT bench, 2026-06-11 backend B1-B8, 2026-06-14 S1, 2026-06-18 S2) — весь history-контекст уже там, постоянный контекст (spec/bench reports) уже в `specs/backend-protocol.md` + `bench/results/REPORT-*.md` + `bench/results/FINAL-CHOICE-TTS-*.md`
- ✅ Переписал `.claude/TASKS.md`: header уточнён («Только открытые: `[ ]`/`[~]`/`[!]`. Закрытые — в CHANGELOG»). Свод-строка вместо sprint dumps: «Сделано: v0.0 foundation, W1–W5 STT bench, backend B1–B9, S1, S2 — детали в CHANGELOG.»
- ✅ Подсчёт после: **0 `[x]`** entries (требование выполнено), 34 open + 1 in-progress, 114 строк (с 219 → -105)
- ✅ Сохранены все открытые элементы: mac-home onboarding 3 items, G0 Gemini deferred, W4-Speech debug deferred, B9-deploy, G2-real-Happy (rename из «G2 next»), V0–V10 VK transport (full block), C3 in-progress + C9 backlog, G1+G3 glue, T1-T4 tests, v0.2 backlog, Backlog post v0.1, Open questions/risks, Operational TODO post-S1, Next stories (S3 + B-Happy-real-bind)

**Решения:**
- **Не добавил локальное правило в проектный `CLAUDE.md`** — глобальное правило self-explanatory, voice не требует override (sprint workflow стандартный, нет специфики типа cashflow TPP-ladder)
- **G2 разделён на 2 ticket'а** — `G2-real-Happy` (real iPhone tap E2E с live Happy) переехал в Backend post-S2 секцию, manual smoke `G2` (cashflow JSONL probe) убран (S2 E2.6 покрыл смежный сценарий — реальный E2E уже зелёный, осталось только bind real Happy session, не smoke)
- **C3 [~] сохранён**, не удалён — это in-progress (Mac run target отложен sim-only), не закрыт. По глобальному правилу `[~]` это open variant.
- **Sprint summary одной строкой** vs ссылка на CHANGELOG: выбрал один inline указатель в header («Сделано: ...») чтобы reader сразу видел scope закрытых без открытия CHANGELOG. CHANGELOG — для деталей.

**Открытое:**
- В `git status` ~8 файлов B9 EnvComposition still uncommitted (вне scope этой session — это работа из прошлой /endsession 2026-06-18 commit ff686f0, видимо partial commit). Sergey: разгребай отдельным `voice:` commit'ом, не блокер для cleanup.
- В TASKS лежит `bench/results/gemma/` как untracked — gitignore селективно для CSV. Не блокер.
- Memory updates не делал — cleanup task не требовал.

**Файлы:**
- .claude/TASKS.md (219 → 114 строк, -105 lines, 0 `[x]`)
- .claude/CHANGELOG.md (этот prepend)

## [2026-06-18] S2 Forward to Happy + bubble UI CLOSED — 6 E-tickets, 41/41 SPM, real E2E green

**Сделано:**
- ✅ **E2.1** Turn value-type (`Sources/VoiceAssistant/Models/Turn.swift`) + ReplyOutcome enum (.pending/.success(Reply)/.failure(String)) + TurnView SwiftUI (`Sources/VoiceAssistant/UI/TurnView.swift`) — 5 TurnTests, .gitignore разлепил `Models/` (был glob, теперь root + Resources/whisperkit only)
- ✅ **E2.2** TurnsStore @Observable class — FIFO cap=10 (configurable), append/updateReply — 6 TurnsStoreTests
- ✅ **E2.3** DispatcherAdapter HTTP real impl — POST /v1/voice/intent + Bearer + JSON {text, client_id, ts ISO8601} + 15s timeout per spec. BackendError +`.forbidden`. Error matrix 401/403/429/503/500-599. 9 DispatcherAdapterTests + dedicated `DispatcherMockURLProtocol` (sibling suite раздружили — Swift Testing параллелит suites, shared static mock racing)
- ✅ **E2.4** IntentPipeline glues transcript → BackendAdapter.send → TurnsStore. Pending turn append BEFORE await чтобы query bubble сразу видна. Error labeling в pipeline (`label(for: BackendError)`) shared между будущими клиентами. ContentView refactored: TurnsStore @State + ScrollView/LazyVStack of TurnView + autoscroll. 5 IntentPipelineTests + FakeBackendAdapter
- ✅ **E2.5** Keychain integration — `TokenStore` protocol + `InMemoryTokenStore` (NSLock guarded, init(initial:) seed) + `KeychainTokenStore` (kSecClassGenericPassword, idempotent write via update-then-add). `OnboardingView` sheet (NavigationStack + monospaced TextField + interactiveDismissDisabled when empty). ContentView wire: .task on launch → read() → если nil, sheet; hold-button disabled until token; header key-icon rotation. 5 InMemoryTokenStoreTests
- ✅ **E2.6** End-to-end smoke via curl from mac-home loopback. Whisper FastAPI **relocated to ubuntu-home** (dual-boot, RTX 3070 CUDA, faster-whisper-large-v3-turbo). Backend restarted (`STT_MODE=live WHISPER_URL=http://192.168.88.13:8000`). Sample `assets/bench/raw/1a-quiet.m4a` (14.6s RU) → S1 200 OK 640ms «Сегодня вторник, нужно успеть в магазин...», S2 200 OK 8ms `[live reply] ...`
- ✅ **Infra fixes (вне S2-scope, но closed по пути):**
  - LAN adapter swap на mac-home (Thunderbolt 2.5Gbps Realtek RTL8156) — **новый MAC 74:D7:AE:00:3A:64**, IP 192.168.88.35 (Wi-Fi MAC 00:E0:6C:6A:63:44 теперь mortв)
  - ubuntu-home Whisper setup — venv на NTFS, `nvidia-cublas-cu12 + nvidia-cudnn-cu12` (ctranslate2 нуждается в CUDA 12 runtime, а driver был 13.2), `LD_LIBRARY_PATH` explicit
  - caffeinate LaunchAgent проблематика — bg ssh trick рабочий для удалённого удержания awake (см. memory)
  - XcodeGen build from source (mac-home + mac-work), regen iOS project включает новые UI/Models/Backend файлы
- ✅ **Tests:** 41/41 SPM green (Turn 5 + TurnsStore 6 + DispatcherAdapter 9 + IntentPipeline 5 + TokenStore 5 + старые 11). iOS BUILD SUCCEEDED on mac-home + mac-work.
- ✅ **Memory updates:** reference_mac_home_clamshell обновлён про bg ssh trick + LaunchAgent disabled status + Sequoia/Tahoe non-interactive bug. Новый reference_ubuntu_home_whisper. Global `~/.claude/docs/home-machines.md` обновлён про caffeinate -dims vs -di + macOS ssh non-interactive bug.

**Решения:**
- **URLSession в iOS, AsyncHTTPClient только в backend** — carry-over предупреждал «AsyncHTTPClient в S2», но crash macOS 26.4 был Hummingbird-async-handler-specific, iOS client safe. Не плодим deps.
- **Turn модель в Models/, View в UI/** — clean separation. Modeli pure value, View не unit-tested per TESTING.md §1.
- **Goodhart-резистентность tests:** TurnTests тестируют публичный API только. Header check Content-Type точное равенство — намеренный цемент (wire contract).
- **Whisper на ubuntu-home** — dual-boot машина, NTFS shared даёт огромный bonus: HF cache (5 моделей включая large-v3-turbo) уже скачан, server.py Linux-compatible. Не дублируем models на ext4.
- **`OnboardingView` sheet sees only `TokenStore` protocol** — UI testable через InMemoryTokenStore fake, Keychain тестируется manual в sim per TESTING.md §"mock только boundaries".

**Открытое:**
- **S3** (TTS reply via 3-tier Yandex/XTTS/Apple) — 8 E-тикетов в `bench/results/FINAL-CHOICE-TTS-2026-06-14.md` (E3.1–E3.8). Tier 1 cloud Yandex как primary, XTTS-v2 secondary, Apple Milena fallback. API key Yandex уже в `~/.config/voice-bench/yandex_speechkit.env` на mac-home.
- **Real Happy session bind** в backend `/v1/voice/intent` — сейчас отвечает `[live reply] <transcript>` echo (B-серии stub), реальный HappyInjectMessenger не запускается. Отдельный B-ticket: HappyState lookup по cwd `/Users/flyer2001/projects/voice-assistant/` (или передать override через env).
- **Backend persistence:** `voice-service` живёт пока bg ssh держит его, и в bad state после многократных mac sleep циклов (PID 44156 был wedged, потребовался pkill+restart). Persistent LaunchDaemon — actionable. Whisper FastAPI на ubuntu-home аналогично — systemd unit на actionable.
- **macOS Sequoia/Tahoe ssh non-interactive bug** — `nohup`/`screen`/`setsid` не выживают close of ssh; sustained work через mac-home требует либо открытой крышки, либо bg ssh trick (`Bash run_in_background:true`), либо NOPASSWD sudo + LaunchDaemon. Sergey может выбрать вариант.

**Файлы:**
- Sources/VoiceAssistant/Models/Turn.swift, TurnsStore.swift (новые)
- Sources/VoiceAssistant/UI/TurnView.swift (новая)
- Sources/VoiceAssistant/Backend/{BackendAdapter,DispatcherAdapter,IntentPipeline,TokenStore,KeychainTokenStore}.swift (DispatcherAdapter — переписан; rest — новые)
- iOS/VoiceAssistant/ContentView.swift (pipeline refactor + Keychain wire)
- iOS/VoiceAssistant/OnboardingView.swift (новая)
- Tests/VoiceAssistantTests/{TurnTests,TurnsStoreTests,DispatcherAdapterTests,IntentPipelineTests,TokenStoreTests}.swift (новые)
- .claude/{TASKS,CHANGELOG,STORIES}.md (TASKS S2 closed)
- .gitignore (anchor /Models/ → root + Resources/whisperkit/)
- Глобально: ~/.claude/docs/home-machines.md (macOS ssh non-interactive + caffeinate -dims)
- Memory: reference_mac_home_clamshell, reference_ubuntu_home_whisper (new), MEMORY.md index


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


