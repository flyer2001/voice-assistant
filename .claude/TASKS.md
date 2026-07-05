# TASKS — voice

> Active sprint. Only open items: `[ ]` open, `[~]` in-progress, `[!]` blocked.
> Закрытые задачи — в `.claude/CHANGELOG.md` (prepend через `/endsession`).
> Сделано: v0.0 foundation, W1–W5 STT bench, backend B1–B9 (incl. EnvComposition split), S1 Speech echo, S2 Forward to Happy + bubble UI, B-Happy-bind verified end-to-end via curl, **MVP_thin² VK voice in / text out E2E green 2026-06-23**, **OP1 Whisper systemd unit на ubuntu-home 2026-06-23**, **async callback + TTS + dual channel 2026-07-05** — детали в CHANGELOG.

---

## Phase 6 — C hybrid multi-project focus routing (next sprint)

**Цель:** voice → правильная session напрямую, dispatcher не оверлоадится.

Sergey markup'ом переключает focus (voice-backend routing), проектные sessions отвечают в VK сами через `voice-reply-*` (async callback уже готов).

### F1 — Focus state file (backend)

- [ ] `/var/lib/voice-bot/focus.json` — schema `{cwd, since, set_by_msg, note}` (все optional; отсутствие или `cwd=null` → default = dispatcher)
- [ ] `FocusState.swift` в VoiceServiceCore: read/write atomic (tmp + rename), validate cwd существует, session running check через HappyState.pickRunningSession (fallback → dispatcher если session offline)
- [ ] Init file если отсутствует: `{"cwd": null}` при первом запуске
- [ ] Tests: read/write roundtrip, missing file → default, cwd invalid → default, session offline → default с fallback log

### F2 — Pipeline routing (backend)

- [ ] `VoiceMessagePipeline` перед `injectNoWait` peek `focus.json`
- [ ] Если valid focus → target_cwd = focus.cwd; иначе default (текущий env `VOICE_TARGET_CWD`)
- [ ] Audit добавляет `target_cwd` + `focus_source` (`focus.json` | `default` | `fallback_offline`) fields
- [ ] Tests: S9 focus set + running → routes to focus. S10 focus set + offline → fallback + log. S11 focus null → default

### F3 — Focus commands (dispatcher)

- [ ] Dispatcher memory `feedback_voice_focus_commands.md` в assistant:
  - «focus X» / «работаем с X» / «в X» → парсит X, пишет focus.json
  - «выйти» / «назад» / «вернись» → cwd=null
  - «в X: <текст>» (one-shot без смены focus) → inject.mjs → воис не меняет focus
  - «статус всех» / «что везде» — dispatcher spike (list_active + summary) не меняя focus
- [ ] Update pipeline prefix hint: упомянуть focus commands + текущий target_cwd

### F4 — Global voice reply protocol

- [ ] Переписать `~/.claude/CLAUDE.md` — добавить секцию «Voice reply» с wrappers references
- [ ] Убрать / упростить `reference_voice_reply_protocol.md` в assistant memory (не дублировать)
- [ ] Каждая проектная session автоматически знает как отвечать

### F5 — Pattern analyzer (on-demand skill)

- [ ] `docs/voice-patterns.md` — spec pattern analysis format + input sources
- [ ] Skill / prompt template: subagent читает `audit.jsonl` + dispatcher JSONL за N дней, корреляция ±30s
- [ ] Output: `bench/analytics/voice-patterns-YYYY-MM-DD.md` с топ-N n-grams, verb frequencies, project mentions, focus events, bad transcriptions (heuristic), dispatcher tool-call overhead per intent
- [ ] Propose canned shortcuts → v0.3 intent-shortcuts backlog items
- [ ] Zero infra в prod, всё on-request

**AC (acceptance criteria):**
- Sergey говорит «focus cashflow» → следующий войс лендит в cashflow session (проверить audit target_cwd) → cashflow отвечает voice-reply-both сам → Sergey получает reply от cashflow, не dispatcher
- Sergey говорит «выйти» → следующий войс снова в dispatcher
- Sergey говорит «в voice: покажи tasks» → один войс в voice session, focus не меняется
- Sergey запросил «/voice-patterns week» → отчёт с 10+ фразами и рекомендациями появляется в bench/analytics/

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
