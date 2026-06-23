# TASKS — voice

> Active sprint. Only open items: `[ ]` open, `[~]` in-progress, `[!]` blocked.
> Закрытые задачи — в `.claude/CHANGELOG.md` (prepend через `/endsession`).
> Сделано: v0.0 foundation, W1–W5 STT bench, backend B1–B9 (incl. EnvComposition split), S1 Speech echo, S2 Forward to Happy + bubble UI, B-Happy-bind verified end-to-end via curl, **MVP_thin² VK voice in / text out E2E green 2026-06-23**, **OP1 Whisper systemd unit на ubuntu-home 2026-06-23** — детали в CHANGELOG.

---

## MVP — operational hardening (Phase 3)

- [ ] **OP3**: assistant Happy session keep-running на VDS. Сейчас target,
  ручной запуск через windows-setup. Auto-restart через `happy --reattach`
  не нужен на MVP — Sergey запускает руками когда работает.

## MVP — dogfood / nice-to-have

- [ ] **DG1**: 5+ голосовых разных типов (короткие, длинные, code-mix,
  shumно) для bench audit. Cumulative WER vs VK-transcript когда оба есть.
- [ ] **DG2**: Happy reply latency variance — msg179 (44s audio) дало
  inject_ms=27.6s. Большая нагрузка диспетчера или большой output? Логировать
  prompt/output sizes в audit для корреляции.
- [ ] **DG3**: VOICE_MAX_AUDIO_S=300 — verify edge cases 290s / 295s / 305s
  (5 min VK upper bound).

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
