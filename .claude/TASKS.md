# TASKS — voice

> Active sprint. Only open items: `[ ]` open, `[~]` in-progress, `[!]` blocked.
> Закрытые задачи — в `.claude/CHANGELOG.md` (prepend через `/endsession`).
> Сделано: v0.0 foundation + mac-home prep, W1–W5 STT bench (bench/results/REPORT-2026-06-10.md, REPORT-LONGFORM-2026-06-11.md), backend B1–B9, S1 Speech echo, S2 Forward to Happy + bubble UI — детали в CHANGELOG.

---

## v0.1 client mac-home onboarding

- [ ] First mac-home Claude session — seed reading: README.md → CLAUDE.md → docs/mac-home-setup.md → .claude/TESTING.md → .claude/TASKS.md → MEMORY.md
- [ ] Spike: `claude mcp list` на mac-home — verify xcodebuild + cupertino MCPs available
- [ ] Spike: build empty iOS app target из Xcode через XcodeBuildMCP, verify simulator boots + screenshot работает

---

## v0.1 — E2E (DoD: capture→reply ≤ 4с)

### Deferred decisions

- [ ] **G0**: Gemini LLM role — v0.3 candidate (intent classifier) ИЛИ post-STT rewrite. Не блокирует v0.1.
- [ ] **W4-Speech**: SpeechTranscriber debug (iOS 26.5 empty output) — отложено.

### Backend post-S2

- [ ] **B9-deploy**: `swift build -c release` на mac-home + restart background ssh holding voice-service после EnvComposition split (см. CHANGELOG 2026-06-18 «B-Happy-bind»).
- [ ] **G2-real-Happy**: Real iPhone tap E2E с `STT_MODE=live` + `HAPPY_MODE=live` + `VOICE_TARGET_CWD=/root/projects/cashflow` — закрывает manual AC story S2.

### Backend extension — VK transport (V-tier)

> Reuse: `tg-client/feature/vk-bot-bridge` спайк (1055 LOC Swift) + RFC v0.6.0 Long Poll migration. См. memory `reference_vk_bot_bridge_spike.md`.
> **DoD V-phase**: voice in (через ВК) → STT → Happy inject → text reply → TTS → voice out (через ВК).

- [ ] **V0**: Cherry-pick `Sources/BotBridge/` infrastructure из tg-client → `backend/voice-service/Sources/VKAdapter/`:
  - VKAPIClient (REST messages.send) + adapt to AsyncHTTPClient (без Hummingbird для Long Poll)
  - VKModels (Codable types) + extend с AudioMessageAttachment + DocsSaveResponse shapes
  - BotSessionState (per-owner state)
  - Battle findings B-02/B-05/B-08/B-09 (см. spike RFC раздел 1.2)
- [ ] **V1**: Long Poll loop — `VKLongPollClient` actor. groups.getLongPollServer + poll {server}?act=a_check&wait=25. Handle failed:1 (ts), failed:2,3 (refetch). TDD: MockHTTPClient.
- [ ] **V2**: Receive — parse `message_new` events. Text → HappyInjectMessenger.send. audio_message attachment → save link_ogg URL для V3.
- [ ] **V3**: Voice STT — download link_ogg → IF VK transcript_state="done" use it ELSE send to Whisper turbo (ubuntu-home endpoint). Audit log decision.
- [ ] **V3a**: FastAPI Whisper turbo на ubuntu-home уже стоит (см. memory `reference_ubuntu_home_whisper`) — только wire backend client.
- [ ] **V4**: Send text reply — VKAPIClient.messages.send peer_id=<owner_id> message=<text>.
- [ ] **V5**: TTS install — Piper TTS на VDS (`~/piper/piper/piper` + voices/ru_RU-irina-medium.onnx + en_US-lessac-medium.onnx). См. memory `reference_tts_piper.md`.
- [ ] **V6**: TTS pipeline — Swift Process wrapping `piper --output_raw | ffmpeg -c:a libopus -b:a 24k -ar 16000 -ac 1 -f ogg`. Streaming pipe.
- [ ] **V7**: RU text normalizer ДО TTS — `num2words[ru]` или Swift regex.
- [ ] **V8**: Voice send pipeline — docs.getMessagesUploadServer (type=audio_message, peer_id) → multipart POST file → docs.save → messages.send + attachment=doc{owner_id}_{id}.
- [ ] **V9**: E2E smoke — voice mailbox endpoint в личке VK community.
- [ ] **V10**: Audit log JSON per request: `{owner_id, peer_id, cmd:"voice_intent", stt_source, stt_ms, inject_ms, tts_ms, total_ms, decision}` → /var/log/voice-vk.jsonl.

### Client (iOS app) — backlog

- [~] **C3**: Mac run target — отложено, sim-only сейчас (iPhone 17 на mac-home Xcode 26).
- [ ] **C9**: secrets.local (Mac dev override) — backlog.

### Glue / observability

- [ ] **G1**: Latency measurement — клиент логгит `capture_ms + transcribe_ms + network_ms + backend_ms + render_ms`. Цель ≤ 4с total.
- [ ] **G3**: First `/endsession close` cycle — CHANGELOG.md prepend, doc-апдейты, commit. (G2 разделён на G2-real-Happy выше + manual smoke ниже.)

### Tests (TDD-discipline per `.claude/TESTING.md`)

- [ ] **T1**: Unit-тесты per TDD-ladder (Triangulation Empty→Single→Multiple).
- [ ] **T2**: Component тест — DispatcherAdapter ↔ URLProtocol mock — все error paths (401, 429 retry_after_ms, 503, timeout).
- [ ] **T3**: E2E happy-path с FakeAudioSource + FakeTranscriber + URLProtocol mock backend.
- [ ] **T4**: Latency budget test — fake-end-to-end в синтетическую 1с budget с fake-clock.

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
  Текущая реализация (commit a94ab30) работает на iOS 17.0.
- Background PTT: custom BLE GATT device (ESP32-C3 / nRF52) если потребуется press
  detection вне foreground — ZMK keyboard-mode foreground-only по дизайну iOS.
  См. memory `reference_bt_button_ios_ptt.md`.

---

## Open questions / risks (live)

- Whisper `base` на iPhone 15 — будет ли реально ≤ 600ms? Замерить в v0.2 первой задачей.
- Global hotkey conflicts с другими apps — заложить option (другая комбинация в settings) в v0.1, иначе блокер.
- Microphone permission flow на macOS Sequoia (15+) изменился — research-first перед C4.

---

## Operational TODO (post-S1)

- [ ] `voice-service` на mac-home как launchd service (сейчас держится через background ssh, тянется только пока есть claude-сессия). См. `~/Library/LaunchAgents/`.
- [ ] Whisper FastAPI на ubuntu-home как systemd unit (сейчас через WMI-like trick — переживает ssh disconnect, но не reboot).
- [ ] Sergey: `sudo pmset -a sleep 0 disksleep 0` на mac-home (см. `reference_mac_home_clamshell` memory — иначе SSH/WG отваливаются в clamshell mode).
- [ ] Удалить временные spike-артефакты на mac-home: `/tmp/spike-hb/`.

## Next stories

- **S3** Voice reply via TTS (3-tier Yandex/XTTS/Apple) — 8 E-тикетов в `bench/results/FINAL-CHOICE-TTS-2026-06-14.md`. Tier 1 cloud Yandex primary, XTTS-v2 secondary, Apple Milena fallback. API key Yandex уже в `~/.config/voice-bench/yandex_speechkit.env` на mac-home.
- **B-Happy-real-bind** Backend `/v1/voice/intent` сейчас echo (`[live reply] <text>`) — нужен HappyState lookup по cwd `/Users/flyer2001/projects/voice-assistant/` (или env override). Отдельный B-ticket после G2-real-Happy.
