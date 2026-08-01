# BACKLOG — voice

> Аспирационное и заблокированное железом/деньгами. Не sprint.
> Исполняемое с done-signal → [`TASKS.md`](TASKS.md).
> Правило переноса: нет действия, которое можно сделать сегодня → сюда.

---

## voice-agent-mac — Fable-standalone архитектура (superseded)

`docs/voice-agent-mac-mvp-plan.md` T1–T12 описывают **другой** агент:
локальный `agent.py` (whisper → Claude Fable 5 API → TTS chunker → player)
с собственным `/v1/voice/notify` endpoint.

По факту 2026-07-17 построен иной loop — whisper local → HTTPS POST →
Happy inject в Claude-сессию → `voice-mac-reply-both` → afplay. Работает,
Fable-версия не нужна пока не появится требование «агент без Claude-сессии».

- [ ] T2: Claude Fable 5 API (model ID, streaming, latency)
- [ ] T3: voice-backend `/v1/voice/notify` endpoint (POST + in-memory queue)
- [ ] T4: `voice-notify <text>` wrapper через install-project.sh
- [ ] T5: agent.py chain (whisper → Fable → TTS chunker → player)
- [ ] T6–T9: TDD components (Config, EventLogger, TTSChunker, NotificationPoller)
- [ ] T12: session notification E2E (другая сессия → voice-notify → наушники)

Reopen если: нужен voice-агент, не привязанный к живой Claude-сессии.

## voice-agent-mac — отложенные фичи

- [ ] **Streaming TTS chunks** (US-4) — reply одним куском. Разбить на
      предложения (первое слово через 1-2с). Требует `max(fresh)` →
      `sorted(fresh)` цикл в `t3-mac-fire-and-poll.py:238` + split в
      `voice-mac-auto-reply.sh`. Deferred до dogfood feedback
- [ ] **HYP-028 full whisper benchmark** — corpus 4 пары × 5s/15s готов в
      `docs/whisper-benchmark-plan.md`. Прогнать когда accuracy станет проблемой

---

## Phase 6 — F3-full voice-command NLP

F3-lite (VK slash `/focus`) + F3-voice (bash wrappers) покрывают use case.
Reopen только под сложные intents (флаги, one-shot patterns).

- [ ] «в X: <текст>» one-shot pattern без смены focus
- [ ] «статус всех» dispatcher spike (list_active + summary)
- [ ] Skill wrapper `/voice-patterns [Nd]` — если понадобится shortcut

---

## Phase 2 — iOS/macOS app (post-MVP)

- [ ] iOS client reuse VK transport как `BackendAdapter` impl
- [ ] G2-real-Happy: iPhone tap E2E (manual AC story S2)
- [ ] G1: latency measurement
- [ ] C9: secrets.local (Mac dev override)
- [ ] Shared SwiftUI Bubble component iOS + macOS
- [ ] UI snapshot тесты state-dump style
- [ ] Doc-drift tests

---

## Phase 7 — MCU wearable client (BC-гарнитура + PTT, non-BT)

Мотивация: iPhone-клиент упирается в push/background/dev-account. Sergey от
BT-наушников быстро болит голова → non-BT wearable, костная проводимость.
Полная архитектура: [`docs/mcu-client.md`](../docs/mcu-client.md).

**Блокер: гарнитура.** Vostok HBT-3 бракованный (speaker Tip↔Sleeve = 0 Ω
при spec 10 Ω), возврат через krikam.net 2026-07-13. Без рабочей гарнитуры
P2–P5 не стартуют.

### P0. macOS UX prototype (FIRST — до траты денег)

Scaffold: `clients/macos-ptt/*` (~350 lines, без TDD). Spec
[`docs/macos-ptt-mvp-spec.md`](../docs/macos-ptt-mvp-spec.md), week-log
[`docs/macos-ptt-week-log.md`](../docs/macos-ptt-week-log.md).
Решения 2026-07-08: backend flow = STT+intent, hotkey = Right Option (61),
transcript в JSONL полностью, cancel-gesture обязателен (US-8).

- [ ] TDD refactor scaffold: Config → EventLogger → BackendClient →
      IntentClient → AudioRecorder (protocol+Fake) → HotkeyMonitor → AppDelegate
- [ ] US-8 cancel-gesture (Escape во время hold)
- [ ] IntentClient (второй HTTP hop: text → /v1/voice/intent → Happy reply)
- [ ] README: install + jq analysis examples + week-log workflow
- [ ] Build на mac-home + первый живой PTT с JSONL evidence
- [ ] 1 неделя dogfooding + week-log.md → decide continue Phase 7

### P1. NanoESP32-C6 v1.0 stand-test

MuseLab NanoESP32-C6 v1.0, ESP32-C6-WROOM-1-N8, 8МБ flash, 512КБ SRAM,
**без PSRAM**, 2× USB-C (UART + native USB/JTAG), RGB LED на GPIO8.

- [ ] P1a: WiFi connect + HTTPS POST на voice-backend
- [ ] P1b: Deep sleep + GPIO wake benchmark (latency, sleep current)
- [ ] P1c: RGB LED status (idle/recording/uploading/error)
- [ ] P1d: TLS reconnect на iPhone hotspot / home WiFi
- [ ] P1e: OneButton + chord matcher state machine (без audio)

### P2. Закупка + testbench audio flow

- [ ] Order: CoreS3 SE + Module Audio ES8388 + Kenwood K1 female socket
- [ ] Testbench с Bose QC25 (TRRS, CTIA)
- [ ] I2S capture 16kHz mono → WAV на SD → play через тот же jack
- [ ] Opus encode + HTTPS chunked POST → voice-backend
- [ ] PTT-эмуляция двумя проводками (short GPIO to GND через pull-up)

### P3. Гарнитура + сборка

- [!] Vostok HBT-3 #1 — бракованный, возврат 2026-07-13 (гарантия 6 мес)
- [ ] Отправить обратно + получить замену (1-2 нед)
- [ ] Замерить новый экземпляр перед распаковкой polyfoam
- [ ] Baofeng BC-K1 (~1.5к) для параллельной sanity check концепта
- [ ] DIY распайка PTT-line на GPIO + chord matcher — после рабочей гарнитуры

### P4. Firmware: light-sleep + pre-roll + chords

- [ ] Light sleep 1-2 мА + I2S DMA ring buffer в PSRAM always-on
- [ ] Wake от PTT GPIO → beep 50мс → чтение буфера (pre-roll 200мс)
- [ ] Wake latency ≤500мс от нажатия до записи
- [ ] Chord bindings в JSON: hold/click/double/triple/CHC/CCH

### P5. 3D-корпус + wearable

- [ ] CAD (Fusion/OnShape): PETG, клипса на ремень 40мм, прорезь под 2"
      экран, USB-C сбоку, 2 K1 jack'а (3.5+2.5mm, центры 11-12мм)
- [ ] Зарезервировать место под extra battery — 54×54×20мм под Battery
      Bottom (M-Bus) либо отсек 20×70×10мм под LiPo/18650. Выбор после
      dogfooding 500 мАч
- [ ] Печать (Bambu/Prusa) или 3D-hub
- [ ] Assembly + polish

**Future (v0.2+):** LoRa Bottom, ESP-MESH, USB QWERTY OTG, custom slim PCB

---

## Deferred / research

- [ ] **G0**: Gemini LLM intent classifier — v0.3 candidate
- [ ] **W4-Speech**: SpeechTranscriber debug iOS 26.5
- [ ] v0.3 intent shortcuts (regex на VDS)
- [ ] v0.5+ iOS Shortcut, Apple Watch, SwiftData history
- [ ] Repo rename `voice` → бренд (перед public-share)
- [ ] License decision: AGPL-3.0 dual vs BSL vs proprietary
- [ ] Hardware-key refactor: SwiftUI `.onKeyPress` (iOS 17.4+)

## Passive / дата-триггерное

- [ ] **DG1** dogfood quality feedback — bot echo'ит «👂 услышал», плохая
      расшифровка → Sergey пишет «msg N плохо: X», паттерн post-hoc.
      Частично superseded F5 pattern analyzer. Structured corpus = overkill
- [ ] **OP3** assistant Happy session keep-running на VDS — ручной запуск,
      MVP не требует
- [ ] Audit JSONL eviction — cron `find /var/lib/voice-bot/raw -mtime +90
      -delete` когда disk usage >2GB

---

[← TASKS.md](TASKS.md) · [CHANGELOG.md](CHANGELOG.md)
