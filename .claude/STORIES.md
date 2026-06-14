# Stories — voice v0.1

> **Story** = что видит пользователь. **DoD** = что считается «готово».
> **E-тикет** = техническая подзадача внутри story, единица TDD-работы
> (один failing test → один impl шаг). Live tasks of all E-тикетов — в
> [TASKS.md](TASKS.md) под соответствующей story-секцией.

История разработки: спайк-фаза до 2026-06-13 (commits до b28e2f6) — это
prototyping без формальных stories, чтобы понять «что вообще возможно».
Дальше всё новое идёт через stories.

---

## S1 — Speech echo

**Как пользователь:** на iPhone нажимаю и удерживаю кнопку, говорю «сколько
денег на счету», вижу на экране транскрипт «сколько денег на счету».

**DoD:**
- Touch-and-hold → AVAudioEngine capture (уже есть, C4)
- Release → upload audio к backend
- Backend выполняет STT, возвращает text
- Client рендерит transcript в footer (или новый bubble)
- НЕТ Happy inject, НЕТ TTS reply, НЕТ persistent history (всё в v0.1 → S2/S3)

**Acceptance criteria** (как руками проверить):
1. Запись 2-3 sec на iPhone 17 sim
2. После релиза — в течение 5 sec видим transcript на экране
3. Если backend down — показ ошибки «backend unreachable», state reset в idle
4. Если STT не распознал (silence) — показ «не распознано»
5. Token валидный читается из Keychain (C8 → S2)

**E-тикеты:**
- E1.1 — Spec endpoint `POST /v1/voice/audio` в specs/backend-protocol.md (contract first, no impl)
- E1.2 — Backend mock STT — failing test → impl возвращает `"echo: <bytes-count>"` (без реального Whisper)
- E1.3 — Backend real STT — wait win-home Whisper FastAPI (depends external infra)
- E1.4 — Client `STTUploader` (новый класс в Sources/VoiceAssistant/Backend/) — TDD URLSession multipart POST + parse response + error paths (401/429/503/timeout)
- E1.5 — ContentView wire: после `audioCapture.stop()` → upload → display transcript в footer вместо `[touch] processed at ...`
- E1.6 — E2E smoke на iPhone 17 sim против real backend (mock STT возвращает stub)

**Открытые вопросы:**
- Multipart vs base64 в JSON body? — multipart standard, проще на server side для streaming больших файлов
- File format: client пишет .caf (C4), backend должен принимать .caf или конвертить? — backend конвертит к 16kHz mono WAV перед Whisper (через ffmpeg)
- Max audio duration: 30 sec hard cap (с client side timer)

---

## S2 — Forward to Happy + bubble UI

**Как пользователь:** после транскрипта (S1) система автоматически шлёт
текст в мою текущую Happy сессию (cwd-привязанную), получает ответ
ассистента, показывает в bubble UI.

**DoD:**
- Transcript из S1 → POST `/v1/voice/intent` (existing endpoint, реализован в B-серии)
- Response.reply → новый bubble (или text view) с answer
- Запоминаем последние N=10 turns в memory (не persisted)
- Token из Keychain (E2.5)

**Acceptance criteria:**
1. Скажи «status cashflow» → транскрипт → видим reply ассистента типа «3 open issues»
2. История: 10 последних turns доступны scroll'ом
3. Backend down на этом этапе (после успешного STT) → транскрипт остаётся, reply показывает ошибку

**E-тикеты:**
- E2.1 — Bubble UI компонент `TurnView` (SwiftUI, query → reply pair)
- E2.2 — `TurnsStore` (in-memory ObservableObject, last 10)
- E2.3 — DispatcherAdapter wire (already есть skeleton) — реальный URLSession POST к `/v1/voice/intent` + error paths
- E2.4 — ContentView pipeline: transcript → DispatcherAdapter.send → render reply
- E2.5 — Keychain `TokenStore` (BACKEND_TOKEN), first-launch onboarding prompt
- E2.6 — E2E smoke против real backend

---

## S3 — Voice reply via TTS (3-tier)

**Как пользователь:** после reply (S2) ассистент говорит вслух женским
голосом (Алиса/Yandex), естественной интонацией.

**DoD:**
- Reply text → TTS → audio playback
- Tier 1: Yandex SpeechKit (cloud, alena voice)
- Tier 2: XTTS-v2 (local server fallback, voice cloning через reference WAVs)
- Tier 3: Apple AVSpeechSynthesizer Milena (iPhone built-in, всегда работает)
- Routing: timeout / error на каждом уровне → fallback

**Acceptance criteria:**
1. Reply «3 open issues» → слышим женский голос ~2 sec после
2. Wi-Fi off → fallback на XTTS server (если доступен через VPN/local) → fallback на Apple
3. Latency budget reply→audio start: 3 sec total (Tier 1), 5 sec (Tier 2), 1 sec (Tier 3)

**E-тикеты:** см. FINAL-CHOICE-TTS-2026-06-14.md (E3.1—E3.8).

---

## Backlog (post-v0.1, без story рамки)

- v0.3 intent shortcuts
- v0.4 ZMK BLE custom button для background PTT (см. reference_bt_button_ios_ptt)
- v0.5 SwiftData persistent history
- VK transport — отдельный track (V-серия в TASKS.md), параллельный stories

---

## Process

1. Story создаётся здесь до начала work (с DoD/AC).
2. E-тикеты добавляются в TASKS.md под секцией с тем же номером.
3. Каждый E-тикет: failing test commit → impl commit → green test.
4. Story закрывается когда все E-тикеты ✅ и AC manual-tested.
5. Closing commit message: `story S1: speech echo CLOSED — N E-tickets, M tests, AC verified`
