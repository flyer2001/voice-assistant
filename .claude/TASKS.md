# TASKS — voice

> Active sprint. Only open items: `[ ]` open, `[~]` in-progress, `[!]` blocked.
> Закрытые задачи — в `.claude/CHANGELOG.md` (prepend через `/endsession`).
> Сделано: v0.0 foundation, W1–W5 STT bench, backend B1–B9 (incl. EnvComposition split), S1 Speech echo, S2 Forward to Happy + bubble UI, B-Happy-bind verified end-to-end via curl — детали в CHANGELOG.

---

## Scope shift 2026-06-22

iOS/macOS клиент отложен в Phase 2. **MVP неделя 22-29.06 = VK transport only**:
голос в → Whisper → Happy inject → текстовый reply в VK + echo транскрипцию обратно.
TTS skip полностью (см. challenge в session JSONL `MVP voice scope обсуждение`).

Reasoning: VK bot = zero deployment на клиенте. Sergey говорит с любого устройства
без iOS app, без provisioning, без WG client. V0-V4 уже на 80% сделаны (commits
`6ddabbe` + `e03ce9c`). Whisper live на ubuntu-home. Backend live на VDS.

---

## MVP_thin² — VK voice in / text out (target 22-29.06)

> DoD: Sergey шлёт voice message в VK community DM → бот в течение 10s
> отвечает (а) транскрипцией его речи (echo) и (б) ответом диспетчера-Claude
> из running Happy session. Audio raw сохраняется для regression bench.

### Phase 0 — spike checklist (день 1 утро)

- [ ] **SP1**: VK voice message attachment shape — verify `audio_message`
  object имеет `link_ogg` / `link_mp3` / `duration` / `transcript` /
  `transcript_state`. Реальный probe на personal token.
- [ ] **SP2**: VK transcript_state lifecycle — sometimes async, прилетает
  `audio_message_transcript` event после `message_new`. Verify both paths.
- [ ] **SP3**: Audio storage layout pick — `/var/lib/voice-bot/raw/<ts>-<msg_id>.ogg`
  + `audit.jsonl` (append-only). Confirm filesystem perms + size growth budget.
- [ ] **SP4**: Bot identity — owner_id Sergey'я, group_id community, VK API
  token scope (messages + docs). Confirm не slip'ает в commit (env/secrets.local).
- [ ] **SP5**: Happy target_cwd — `/root/projects/cashflow` (если running) или
  отдельная dispatcher session. Confirm.

### Phase 1 — E2E scenarios (текст, для согласования с Sergey)

- [ ] **ES**: Дописать `specs/vk-bot-mvp.md` — 6-8 текстовых сценариев happy/error.
  Не код. После approve → TDD ladder.

### Phase 2 — TDD ladder (после approve ES)

> Порядок: red E2E → red component → red unit → green обратно.

- [ ] **V3**: Voice STT wire — download VK link_ogg → IF transcript_state=done
  use VK transcript ELSE Whisper turbo. Save both в audit для compare.
- [ ] **V4-echo**: Echo транскрипции обратно в VK DM **перед** inject в Happy.
  Sergey видит «что бот услышал» сразу.
- [ ] **V4-inject**: Happy inject с prefix `[voice from Sergey, src=vk|whisper, lang=ru]\n<text>`.
  Reply из Happy → VK messages.send.
- [ ] **V9**: E2E smoke реально через VK DM. 5 голосовых из dogfood.
- [ ] **V10**: Audit log per request — `audit.jsonl` shape: `{ts, peer_id, msg_id, audio_path, vk_transcript, whisper_transcript, latency_ms, decision, happy_reply}`.

### Phase 3 — Operational hardening (день 5)

- [ ] **OP1**: Whisper FastAPI systemd unit на ubuntu-home (сейчас nohup, не
  переживает reboot). См. CHANGELOG operational TODO.
- [ ] **OP2**: voice-backend.service на VDS уже systemd (CHANGELOG 2026-06-18) —
  verify reboot survival.
- [ ] **OP3**: Cashflow Happy session keep-running (или auto-restart) на VDS.
  Иначе inject fail.

---

## Backlog (post-MVP)

### TTS reply (S3, отложено)

- [ ] **S3.Yandex**: Tier 1 Yandex SpeechKit. См. `bench/results/FINAL-CHOICE-TTS-2026-06-14.md`.
  Triggered только если text-out скучно после dogfood week.

### iOS/macOS app (Phase 2, post-MVP)

- [ ] iOS client reuse VK transport как `BackendAdapter` impl.
- [ ] G2-real-Happy: iPhone tap E2E. Manual AC story S2.
- [ ] G1: Latency measurement.
- [ ] C9: secrets.local (Mac dev override).
- [ ] Shared SwiftUI Bubble component между iOS + macOS.
- [ ] UI snapshot тесты state-dump style.
- [ ] Doc-drift tests.

### Deferred

- [ ] **G0**: Gemini LLM intent classifier — v0.3 candidate.
- [ ] **W4-Speech**: SpeechTranscriber debug iOS 26.5.
- [ ] v0.3 intent shortcuts (regex на VDS).
- [ ] v0.5+ iOS Shortcut, Apple Watch, SwiftData history.
- [ ] Repo rename `voice` → бренд (перед public-share).
- [ ] License decision: AGPL-3.0 dual vs BSL vs proprietary.
- [ ] Hardware-key refactor: SwiftUI `.onKeyPress` (iOS 17.4+).
- [ ] Background PTT: custom BLE GATT (ESP32-C3 / nRF52).

---

## Open questions / risks (live)

- VK rate limit / ToS — Sergey ↔ bot DM only, не group. ~100 msg/day fine.
  См. memory `reference_vk_bot_contracts.md`.
- Whisper `base` на iPhone 15 ≤ 600ms — замерить если iOS app возвращается в скоуп.
- Microphone permission flow macOS Sequoia 15+ — research перед iOS app revival.

---

## Operational TODO (post-MVP cleanup)

- [ ] mac-home: `sudo pmset -a sleep 0 disksleep 0` (см. `reference_mac_home_clamshell`).
- [ ] mac-home: Screen Sharing daemon kickstart после macOS update.
- [ ] Удалить spike-артефакты `/tmp/spike-hb/` на mac-home.
- [ ] voice-service на mac-home как launchd — не нужен если backend остаётся на VDS.
