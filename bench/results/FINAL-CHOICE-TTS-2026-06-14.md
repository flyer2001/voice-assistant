# TTS Provider Final Choice — 2026-06-14

После 5×7 bench (Apple/Yandex/Piper/Silero/XTTS-v2 × 7 phrases) + subjective MOS Sergey'я.

## Aggregated scores

| Провайдер | Естественность | Адекватность | Главное | Главный минус |
|---|---|---|---|---|
| **yandex / alena** | **5.0** | **4.86** | RU-нативно, perfect prosody, понятный EN с RU акцентом | редкое ударение запу́шить |
| xtts-v2 / Claribel Dervla | 3.83 | 4.5 | отличная EN дикция, code-mix native, multilingual | женственности мало, slow на CPU |
| piper / ru_RU-irina-medium | 4.0 | 4.0 | local CPU instant, RU natural | EN не читает понятно |
| silero / baya | 3.67 | 3.17 | local, free | пропускает EN, ударения сле́пые |
| apple / Milena | 2.0 | 2.83 | offline на iPhone | ломаный pronunciation на code-mix |

Note: p3-piper Sergey оставил неоценённым, p5/p4 кое-где пропуски — не влияет на ranking.

## Final 3-tier fallback architecture

```
Reply text
    │
    ▼
┌─────────────────────────────────────────────┐
│ Tier 1: Yandex SpeechKit (alena, RU+EN)     │  primary, ~$0.0001 per phrase
│ ──── if network fail OR cost cap reached    │
│                                             │
│ Tier 2: XTTS-v2 server (Claribel Dervla)    │  local on mac-home/win-home/VDS, free
│        ── if server unreachable              │
│                                             │
│ Tier 3: Apple AVSpeechSynthesizer Milena    │  always available, iPhone built-in
└─────────────────────────────────────────────┘
```

Tier 1 → Tier 2: client-side timeout (e.g. 3 sec) or pre-emptive cost-cap.
Tier 2 → Tier 3: TTS server health-check fail.

## XTTS-v2 — что можно «дотюнить» (без full fine-tuning)

Sergey спросил: "можно ли XTTS дотюнить, описывать ей эмоции, размечать текст по-другому".

Краткий ответ: **fine-tuning не нужен** для emotion control. XTTS-v2 умеет три практичных трюка из коробки:

### 1. Voice cloning из reference WAV (built-in, БЕЗ обучения)

XTTS-v2 принимает 6-30 секундный `speaker_wav` параметр и клонирует voice. Тон/эмоция reference clip передаётся в output. Архитектура:

```
assets/voice-refs/
  neutral.wav     ← 15 sec нейтральной речи
  excited.wav     ← 15 sec бодрого тона
  snarky.wav      ← 15 sec ироничного тона
  soft.wav        ← 15 sec мягкого доверительного
  alert.wav       ← 15 sec тревожного urgency
```

На runtime: classify reply intent → pick ref → `tts.tts_to_file(text=…, speaker_wav=refs[intent], language="ru")`.

Записать reference clips можно через любой recorder или scrub из existing audio (TED talk, YouTube voiceover с public license).

### 2. Text-preprocessing markup (псевдо-SSML)

XTTS не парсит SSML, но реагирует на:
- **Punctuation density** — `!`, `?`, `…` меняют intonation
- **Capitalization** — `BACKEND DOWN!` читается с emphasis
- **Repetition** — "Что-то-что-то" даёт нерешительность
- **Acronym normalization** — "API" → "эй-пи-ай" (через preprocessing на бэкенде до подачи в XTTS)

Wrap в helper: `prepare_for_xtts(text, intent) → normalized_text + voice_ref_path`.

### 3. F5-TTS upgrade — newer 2024 model, эффективнее emotion

Coqui XTTS отстаёт от **F5-TTS** (Microsoft Research, 2024). F5 лучше на:
- Sub-word emotion control
- Faster inference (~2× XTTS)
- Voice cloning из 5 sec reference (XTTS требует 10-30)

Drop-in замена, дороже compute. Можно протестировать на mac-home (M1 Metal).

### НЕ рекомендую

- **Full fine-tuning** — требует 10+ hours custom audio, GPU 24+ часов, ML expertise. Окупится только при коммерческом запуске.
- **CoreML conversion для iPhone on-device** — XTTS ~1.5GB модель, неофициально, месяцы работы port. Лучше Piper iOS port (есть community) или Apple Voices для Tier 3.

## Action items (story-driven)

Story S3 "Voice reply via TTS" разбивается:

- **E3.1** — Spec: `protocol TTSProvider { synth(text: String, intent: Intent?) async throws -> Data }` + `Intent enum { neutral, alert, soft, snarky, ... }`
- **E3.2** — TDD `LiveYandexTTS` (Tier 1) — POST to SpeechKit, return MP3 bytes. Mock через `MockTTSProvider`.
- **E3.3** — TDD `LiveXTTSProvider` (Tier 2) — HTTP к нашему XTTS server (mac-home/win-home/VDS), JSON request with text + intent → audio bytes. Voice-refs хранятся на server side.
- **E3.4** — TDD `LiveAppleTTSProvider` (Tier 3) — AVSpeechSynthesizer wrapper, синхронный, gives PCM buffer.
- **E3.5** — `TieredTTSRouter` — wraps 3 providers, на каждом timeout / error → fallback к следующему. Цена / health checks.
- **E3.6** — XTTS server (Python FastAPI) on mac-home / VDS — wraps Coqui TTS, accepts `{text, intent}`, picks voice-ref, returns mp3.
- **E3.7** — Voice-refs collection: ~10 reference clips для 5 intents × 2 voices.
- **E3.8** — iOS playback through `AVAudioPlayer` после получения audio bytes.

ETA: E3.1-3.5 — 1-2 sessions. XTTS server (E3.6) — отдельная session с win-home/mac-home setup.
