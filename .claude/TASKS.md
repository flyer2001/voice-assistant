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

### Phase 7 — MCU wearable client (BC-гарнитура + PTT, non-BT)

Мотивация: iPhone-клиент упирается в push/background/dev-account. Sergey
от BT-наушников быстро болит голова → нужен non-BT wearable. Костная
проводимость + костный микрофон под шлем/в шум. Полный спек:
[`docs/mcu-client.md`](../docs/mcu-client.md).

**P0-alt. Hands-free voice agent (voice-agent-mac, MVP v0.1)**

**Refactored 2026-07-13** — отказ от OpenAI Realtime (Path A). Идём сразу
на свой стек:
- STT: mlx-whisper local на mac-home (Metal)
- LLM: Claude Fable 5 (Anthropic API)
- TTS: Yandex SpeechKit `alena` через VDS `voice-reply-tts` remote
- Wake: Porcupine custom «Алёнка»

Полный спек: [`docs/voice-agent-mac-mvp-plan.md`](../docs/voice-agent-mac-mvp-plan.md).

**Задачи первой недели (T1-T12 в plan doc):**

- [x] **T0 (2026-07-13):** Восстановлен reverse tunnel VDS↔mac-home
      (autossh config был на старый VDS IP `194.4.49.217`, заменён на
      `cashflow-game.ru` DNS-имя в `~/.ssh/config` `Host ufohosting`).
      На VDS добавлен `mac-home-tunnel` alias через localhost:2222.
- [ ] **T0.1:** Apply mac-home clamshell fix `sudo pmset -a sleep 0
      disksleep 0 tcpkeepalive 1` (per [[reference_mac_home_clamshell]])
      — сейчас sleep=5, mac-home засыпает при закрытой крышке
- [ ] **T0.2:** Install на mac-home базовый tooling:
      `brew install python@3.11 ffmpeg portaudio` +
      `pip install mlx-whisper anthropic pvporcupine sounddevice numpy`
- [ ] **T0.3:** Mount voice-repo через sshfs на mac-home
      (либо клон отдельный)
- [ ] T1: mlx-whisper на mac-home
- [ ] T2: Test Claude Fable 5 API (model ID, streaming, latency)
- [ ] T3: voice-backend `/v1/voice/notify` endpoint
- [ ] T4: `voice-notify <text>` bash wrapper через install-project.sh
- [ ] T5: Rewrite agent.py (whisper → Fable → TTS chunker → player)
- [ ] T6-T9: TDD components (Config, EventLogger, TTSChunker, Poller)
- [ ] T10: Wake word + Escape cancel
- [ ] T11: First E2E dogfood
- [ ] T12: Session notification E2E

**Sergey нужно перед стартом:**
- Anthropic API key (для Claude Fable 5)
- Porcupine access key + train «Алёнка» keyword
- Подтвердить TTS remote vs local

**НЕ нужно:** OpenAI API key (Path A отменён).

**P0. macOS UX prototype (FIRST — до траты денег)**

Scaffold готов: `clients/macos-ptt/*` (~350 lines, без TDD). Spec:
[`docs/macos-ptt-mvp-spec.md`](../docs/macos-ptt-mvp-spec.md). Week-log
template: [`docs/macos-ptt-week-log.md`](../docs/macos-ptt-week-log.md).

Решения 2026-07-08: backend flow = STT+intent, hotkey = Right Option (61),
transcript в JSONL полностью, cancel-gesture обязателен (US-8).

- [ ] TDD refactor scaffold: Config → EventLogger → BackendClient → IntentClient
      → AudioRecorder (protocol+Fake) → HotkeyMonitor (protocol+Fake) →
      AppDelegate integration
- [ ] US-8 cancel-gesture (Escape во время hold)
- [ ] IntentClient (второй HTTP hop: text → /v1/voice/intent → Happy reply)
- [ ] README: install + jq analysis examples + week-log workflow
- [ ] Build на mac-home + первый живой PTT с JSONL evidence
- [ ] 1 неделя dogfooding + заполнение week-log.md → decide continue Phase 7

**P1. NanoESP32-C6 v1.0 stand-test (пока CoreS3 едет)**

Плата: MuseLab NanoESP32-C6 v1.0 (wuxx repo), ESP32-C6-WROOM-1-N8,
8МБ flash, 512КБ SRAM, **без PSRAM**, 2× USB-C (UART + native USB/JTAG),
RGB LED на GPIO8. Годится для всего кроме full-audio pipeline.

- [ ] P1a: WiFi connect + HTTPS POST test payload на voice-backend (через
      native USB-C для быстрого flash + JTAG debug)
- [ ] P1b: Deep sleep + GPIO wake benchmark (wake latency, sleep current)
- [ ] P1c: RGB LED status indication (idle/recording/uploading/error)
- [ ] P1d: TLS reconnect stability на iPhone hotspot / home WiFi
- [ ] P1e: OneButton + chord matcher state machine (без audio)

**P2. Закупка + testbench audio flow**
- [ ] Order: CoreS3 SE + Module Audio ES8388 + Kenwood K1 female socket
- [ ] Testbench с Bose QC25 (обычный TRRS штекер, CTIA стандарт)
- [ ] I2S capture 16kHz mono → WAV на SD → play через тот же jack
- [ ] Opus encode + HTTPS chunked POST → voice-backend
- [ ] PTT-эмуляция двумя проводками (short GPIO to GND через pull-up)

**P3. Гарнитура + сборка**
- [!] Vostok HBT-3 (первый экземпляр) — **бракованный, возврат 2026-07-13**.
      Замер мультиметра: speaker Tip↔Sleeve = 0 Ω (spec 10 Ω, короткое в BC-transducer).
      Mic 6.6 kΩ (off-spec vs 2.2 kΩ но работает). Возврат через krikam.net (гарантия 6 мес).
- [ ] Отправить обратно + получить замену (1-2 нед)
- [ ] Замерить новый экземпляр перед распаковкой polyfoam
- [ ] Baofeng BC-K1 (~1.5к) для параллельной sanity check концепта пока Vostok в возврате
- [ ] DIY распайка PTT-line на GPIO, sanity chord matcher (OneButton) — после рабочей гарнитуры

**P4. Firmware: light-sleep + pre-roll + chords**
- [ ] Light sleep 1-2 мА + I2S DMA ring buffer в PSRAM always-on
- [ ] Wake от PTT GPIO → beep 50мс → продолжение чтения буфера (pre-roll 200мс)
- [ ] Wake latency цель ≤500мс от нажатия до записи
- [ ] Chord bindings в JSON: hold/click/double/triple/CHC/CCH

**P5. 3D-корпус + wearable**
- [ ] CAD (Fusion/OnShape): PETG, клипса на ремень 40мм, прорезь под 2"
      экран, USB-C hole сбоку, hole под 2 K1 jack'а (3.5mm + 2.5mm,
      расстояние центров 11-12мм)
- [ ] **Зарезервировать место под extra battery** — либо посадка 54×54×20мм
      под Battery Bottom (M-Bus стек), либо отсек 20×70×10мм под LiPo pouch/18650.
      Финальный выбор после dogfooding 500 мАч
- [ ] Печать (Bambu/Prusa) или заказ на 3D-hub
- [ ] Assembly + polish

**Future (v0.2+, in [`docs/mcu-client.md`](../docs/mcu-client.md))**
- LoRa Bottom, ESP-MESH, USB QWERTY OTG, custom slim PCB

**Refs:** [`docs/mcu-client.md`](../docs/mcu-client.md) — полная архитектура

### Deferred

- [ ] **G0**: Gemini LLM intent classifier — v0.3 candidate.
- [ ] **W4-Speech**: SpeechTranscriber debug iOS 26.5.
- [ ] v0.3 intent shortcuts (regex на VDS).
- [ ] v0.5+ iOS Shortcut, Apple Watch, SwiftData history.
- [ ] Repo rename `voice` → бренд (перед public-share).
- [ ] License decision: AGPL-3.0 dual vs BSL vs proprietary.
- [ ] Hardware-key refactor: SwiftUI `.onKeyPress` (iOS 17.4+).
- ✅ **Background PTT** (superseded by Phase 7): MCU-client с проводной
      Kenwood-гарнитурой закрывает BLE-PTT tangent. См. Phase 7.

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
