# TTS Provider Bench Report — 2026-06-13 (ElevenLabs dropped)

5 providers × 7 phrases. EN+RU code-mix, humor/snark, alert, tech path.

Subjective scoring: see `SURVEY-TTS-2026-06-13.md` — заполняется Sergey-ем по слуху.

## Summary by provider (technical)

| Provider | Voice | OK / Total | Mean latency | Audio total | Mean file | Total cost | RTF | Notes |
|---|---|---|---|---|---|---|---|---|
| apple | Milena | 7/7 | 466 ms | 27.8 s | 47.7 KB | $0.0 | 0.117 | apple-builtin |
| piper | ru_RU-irina-medium | 7/7 | 201 ms | 31.4 s | 193.3 KB | $0.0 | 0.045 | local ONNX CPU |
| silero | baya | 6/6 | 279 ms | 20.0 s | 312.9 KB | $0.0 | 0.083 | local torch CPU, model=v4_ru |
| xtts-v2 | Claribel Dervla | 7/7 | 6736 ms | 38.5 s | 257.9 KB | $0.0 | 1.224 | local M1 CPU, model=xtts_v2, lang=ru |
| yandex | alena | 7/7 | 643 ms | 30.6 s | 34.2 KB | $0.000965 | 0.147 | v1 sync, lang=ru-RU |

RTF = total latency / total audio duration. < 1 = faster than realtime.

## Per-phrase audio links

### p1-cmd-ru — command_ru

> "Сколько денег на счету?"

_Purpose: Baseline RU прозодия, короткий вопрос_

- **apple** / Milena: [p1-cmd-ru.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p1-cmd-ru.mp3) — 501 ms, 1.52s
- **piper** / ru_RU-irina-medium: [p1-cmd-ru.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p1-cmd-ru.wav) — 516 ms, 1.50s
- **silero** / baya: [p1-cmd-ru.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p1-cmd-ru.wav) — 720 ms, 1.57s
- **xtts-v2** / Claribel Dervla: [p1-cmd-ru.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p1-cmd-ru.wav) — 3814 ms, 2.50s
- **yandex** / alena: [p1-cmd-ru.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p1-cmd-ru.mp3) — 725 ms, 1.81s

### p2-codemix-tech — codemix_tech

> "Push the API endpoint, refactor the adapter."

_Purpose: Чистый EN с тех. терминами — проверка англ. голоса_

- **apple** / Milena: [p2-codemix-tech.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p2-codemix-tech.mp3) — 463 ms, 2.79s
- **piper** / ru_RU-irina-medium: [p2-codemix-tech.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p2-codemix-tech.wav) — 97 ms, 3.12s
- **xtts-v2** / Claribel Dervla: [p2-codemix-tech.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p2-codemix-tech.wav) — 4707 ms, 3.99s
- **yandex** / alena: [p2-codemix-tech.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p2-codemix-tech.mp3) — 519 ms, 3.51s

### p3-codemix-mid — codemix_ru_en

> "Bro, я серьёзно, ты опять забыл deploy запушить?"

_Purpose: RU + EN терминs в одной фразе — главный тест для XTTS / ElevenLabs_

- **apple** / Milena: [p3-codemix-mid.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p3-codemix-mid.mp3) — 451 ms, 3.50s
- **piper** / ru_RU-irina-medium: [p3-codemix-mid.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p3-codemix-mid.wav) — 105 ms, 3.55s
- **silero** / baya: [p3-codemix-mid.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p3-codemix-mid.wav) — 664 ms, 2.80s
- **xtts-v2** / Claribel Dervla: [p3-codemix-mid.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p3-codemix-mid.wav) — 5231 ms, 4.31s
- **yandex** / alena: [p3-codemix-mid.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p3-codemix-mid.mp3) — 687 ms, 3.80s

### p4-alert — alert

> "Внимание! Критическая ошибка в production-сервисе."

_Purpose: Прозодия тревоги, exclamation, дефис в составном слове_

- **apple** / Milena: [p4-alert.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p4-alert.mp3) — 450 ms, 3.74s
- **piper** / ru_RU-irina-medium: [p4-alert.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p4-alert.wav) — 119 ms, 3.88s
- **silero** / baya: [p4-alert.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p4-alert.wav) — 79 ms, 3.19s
- **xtts-v2** / Claribel Dervla: [p4-alert.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p4-alert.wav) — 7141 ms, 6.17s
- **yandex** / alena: [p4-alert.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p4-alert.mp3) — 694 ms, 4.40s

### p5-humor — humor_snark

> "Хе-хе, ну ты, конечно, и придумал. С такой архитектурой далеко не уедешь."

_Purpose: Юмор / ирония — главный субъективный критерий женский голос_

- **apple** / Milena: [p5-humor.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p5-humor.mp3) — 458 ms, 5.42s
- **piper** / ru_RU-irina-medium: [p5-humor.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p5-humor.wav) — 193 ms, 6.73s
- **silero** / baya: [p5-humor.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p5-humor.wav) — 112 ms, 5.36s
- **xtts-v2** / Claribel Dervla: [p5-humor.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p5-humor.wav) — 9314 ms, 7.87s
- **yandex** / alena: [p5-humor.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p5-humor.mp3) — 726 ms, 5.74s

### p6-path-numbers — tech_path

> "Транскрипт записан, файл сохранён в /tmp/recording-2026-06-13.caf"

_Purpose: Как читает путь файла, числа, дефисы_

- **apple** / Milena: [p6-path-numbers.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p6-path-numbers.mp3) — 474 ms, 7.14s
- **piper** / ru_RU-irina-medium: [p6-path-numbers.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p6-path-numbers.wav) — 246 ms, 8.60s
- **silero** / baya: [p6-path-numbers.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p6-path-numbers.wav) — 43 ms, 3.17s
- **xtts-v2** / Claribel Dervla: [p6-path-numbers.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p6-path-numbers.wav) — 10121 ms, 7.84s
- **yandex** / alena: [p6-path-numbers.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p6-path-numbers.mp3) — 705 ms, 7.52s

### p7-soft-question — soft_question

> "Я не уверена в ответе. Может, переформулируешь вопрос?"

_Purpose: Мягкий, доверительный тон — женственность голоса_

- **apple** / Milena: [p7-soft-question.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/apple/Milena/p7-soft-question.mp3) — 465 ms, 3.70s
- **piper** / ru_RU-irina-medium: [p7-soft-question.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/piper/ru_RU-irina-medium/p7-soft-question.wav) — 129 ms, 4.03s
- **silero** / baya: [p7-soft-question.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/silero/baya/p7-soft-question.wav) — 54 ms, 3.92s
- **xtts-v2** / Claribel Dervla: [p7-soft-question.wav](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/xtts-v2/Claribel_Dervla/p7-soft-question.wav) — 6825 ms, 5.84s
- **yandex** / alena: [p7-soft-question.mp3](https://cashflow-game.ru/screenshots/1aa492bf-5009-4651-909f-64d2b06429ce/tts/yandex/alena/p7-soft-question.mp3) — 447 ms, 3.85s

## Known issues

- **ElevenLabs**: dropped from bench — API rejected key (302→help) for both real and invalid auth, regardless of source IP (mac-home/mac-work/VDS all RU). Cloudflare passes mac-work, but EL itself rejects. Likely subscription/scope issue at account level.

- **Silero `p2-codemix-tech`**: pure-EN text rejected by v4_ru ValueError. Expected — silero RU has no English phoneme map.

- **XTTS-v2**: 4-10× slower than realtime on M1 CPU. GPU acceleration would bring sub-second.
