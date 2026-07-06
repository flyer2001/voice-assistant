# TASKS — voice

> Active sprint. Only open items: `[ ]` open, `[~]` in-progress, `[!]` blocked.
> Закрытые задачи — в `.claude/CHANGELOG.md` (prepend через `/endsession`).
> Сделано: v0.0 foundation, W1–W5 STT bench, backend B1–B9 (incl. EnvComposition split), S1 Speech echo, S2 Forward to Happy + bubble UI, B-Happy-bind verified end-to-end via curl, **MVP_thin² VK voice in / text out E2E green 2026-06-23**, **OP1 Whisper systemd unit на ubuntu-home 2026-06-23**, **async callback + TTS + dual channel 2026-07-05** — детали в CHANGELOG.

---

## Phase 6 — C hybrid multi-project focus routing

**Shipped 2026-07-05** (F1/F2/F3-lite/F3-voice/F4/F5). E2E green: manual focus.json → myRep (round 1) + full voice-command flow → /root/projects/voice (round 2). Детали в CHANGELOG.

Остались backlog-items:

### F3-full — Voice-command dispatcher NLP (deferred, likely unnecessary)

F3-lite (VK slash `/focus <name>`) + F3-voice (bash wrappers `voice-focus`/`voice-focus-clear` с alias table) уже покрывают use case:
- Slash-команды — защищены от Whisper mistranslate («кэшфлоу» vs «cashflow»)
- Voice wrappers — hands-free, alias «дневник→myRep», TTS-ack «переключил на X»

F3-full = full dispatcher NLP memory `feedback_voice_focus_commands.md` для нетривиальных фраз («работаем с проектом дневник, только текстом» → set focus + set text-only mode).

Reopen только если понадобится ловить сложные intents (флаги, one-shot patterns и т.д.).

- [ ] «в X: <текст>» one-shot pattern (без смены focus) — если понадобится
- [ ] «статус всех» dispatcher spike (list_active + summary)

### F5 — Pattern analyzer runtime

Spec написан (`docs/voice-patterns.md`). Осталось:
- [ ] Первый прогон subagent'а на реальных 2 неделях audit'а → sanity check spec
- [ ] Skill wrapper `/voice-patterns [Nd]` — если понадобится shortcut

**AC (Phase 6 shipped):**
- ✅ `/focus myRep` в VK → следующий войс лендит в myRep session, audit target_cwd подтверждает
- ✅ `/to_assistant` → следующий войс в dispatcher
- ⏸ «в voice: покажи tasks» one-shot — deferred (F3-full)
- ⏸ `/voice-patterns week` — spec готов, первый run отложен

---

## MVP — dogfood (passive collection)

- [ ] **DG1**: ad-hoc quality feedback. Bot уже echo'ит «👂 услышал: ...».
  Плохая расшифровка → Sergey пишет в любую Claude сессию «msg N плохо: X»,
  собираем паттерн post-hoc. Structured corpus collection — overkill.
  WER vs VK = blocked (skip `audio_message_transcript` event per SP3).
  Частично superseded F5 pattern analyzer (в Phase 6). DG2/DG3 закрыты
  async callback'ом — детали в CHANGELOG.

## MVP — operational (deferred)

- [ ] **OP3**: assistant Happy session keep-running на VDS. Ручной запуск,
  MVP не требует. Sergey запускает через windows-setup когда работает.

---

## Backlog (post-MVP)

### TTS reply

- ✅ **S3.Yandex** (2026-06-24): `voice-reply-tts` bash wrapper. Yandex
  alena oggopus → VK docs upload → messages.send. Total ~3s. VK group
  token re-issued с `docs` scope. Quirk: латинские abbrs читаются криво
  (TTS, API) — пиши кириллицей если важно. Spec'ов и Swift-кода нет —
  bash достаточно.

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
- VK transcript_state async event (`audio_message_transcript`) skip'ается в
  MVP — Whisper всегда работает когда `state != "done"`. Перепроверить
  trade-off если Whisper будет под нагрузкой.
- Audit JSONL eviction policy = NONE (per Phase 0 SP3). ~180KB/msg, OK на
  год. Cleanup cron — когда понадобится, не сейчас.

---

## Operational TODO (post-MVP cleanup)

- [ ] mac-home: `sudo pmset -a sleep 0 disksleep 0` (см. `reference_mac_home_clamshell`).
- [ ] mac-home: Screen Sharing daemon kickstart после macOS update (S5900 не listen).
- [ ] Удалить spike-артефакты `/tmp/spike-hb/` на mac-home.
- [ ] voice-service на mac-home как launchd — не нужен, backend на VDS.
- [ ] Audit JSONL eviction — cron `find /var/lib/voice-bot/raw -mtime +90 -delete`
  когда disk usage станет проблемой (>2GB).
