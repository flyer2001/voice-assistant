# Whisper / Gemma / Apple Speech — STT benchmark plan

> Voice-локальная адаптация бенчмарка из `myRep/_project-hub/hypotheses/HYP-028-voice-ai-infrastructure.md`, секция **«[NEW 2026-06-05] Win-home характеристики + Gemma 4 vs Whisper benchmark plan»**. HYP-028 — источник методологии, метрик и фаз. Этот документ расширяет план под нужды voice-assistant v0.1: **iPhone on-device кандидаты** (WhisperKit, SFSpeechRecognizer, Apple SpeechAnalyzer), **полный корпус команд** с quiet/noisy split, и **GSM-band emulation** для проверки feasibility HYP-045 (voice IVR через звонок).

## Цель

Принять три решения:

1. **W3 (voice v0.1):** on-device (WhisperKit/Apple Speech на iPhone) vs server-side (Whisper/Gemma на VDS или mac-home). Влияет на `specs/backend-protocol.md` — если server-side, добавляем `/v1/voice/audio` endpoint.
2. **Команда vs длинный текст:** какая модель оптимальна для коротких dev-команд (5s) vs более длинных запросов (15s).
3. **HYP-045 go/no-go:** жив ли voice IVR через GSM звонок, или AMR-NB band полностью убивает технические термины. Threshold: ΔWER (clean → amrnb) > 15% = не имеет смысла.

## Тестируемые STT-модели

### Server-side (Win-home + mac-home через SSH)

| Модель | Хост | Backend | Заметки |
|---|---|---|---|
| Whisper Large-v3 | Win-home | faster-whisper CUDA | CUDA на RTX 3070 Laptop быстрее M1 Metal на ~20-30% (HYP-028) |
| Whisper Large-v3 | mac-home | whisper.cpp Metal | Cross-check Mac vs Win, проверить разброс |
| Whisper Medium | Win-home | faster-whisper CUDA | Real-time candidate (RTF target <0.5) |
| Whisper Small | Win-home | faster-whisper CUDA | Edge real-time, если Medium тяжёл |
| Gemma 3n E2B (audio) | Win-home | HF Transformers + PyTorch CUDA | ~2GB VRAM, комфортно на RTX 3070 |
| Gemma 3n E2B (audio) | mac-home | HF Transformers (MPS) или Ollama | Cross-platform reference |
| Gemma 3n E4B (audio) | Win-home | HF Transformers CUDA | ~3GB VRAM |
| Gemma 3n E4B (audio) | mac-home | MLX (если доступен) или HF Transformers | Native Apple Silicon speed |
| Gemma 4 E2B / E4B (audio) | Win-home + mac-home | HF Transformers | Если стабильны (март 2026 release) |
| Gemma 4 12B Unified (audio) | mac-home only | Ollama / MLX | 6-7GB FP16, на Win-home (8GB VRAM) впритык — пробуем только если Q4 quant работает с audio |

**Дополнение к HYP-028:** Gemma — **cross-platform**, не Mac-exclusive. На Win-home через HF Transformers + PyTorch CUDA работают все E-варианты (E2B/E4B) обеих веток (3n и 4). Только большие Gemma 4 (12B/26B/31B) требуют Mac 32GB или больше VRAM. Это даёт нам cross-platform reference — одну модель прогоняем на обеих машинах, понимаем разброс по latency и качеству per backend.

### On-device (iPhone 13 mini, A15 Bionic, 4GB RAM)

**Constraint:** iPhone 13 mini НЕ поддерживает Apple Intelligence (требует A17 Pro+ / 8GB RAM) — Foundation Models LLM и Siri AI (WWDC 2026) недоступны. STT-стэк работает, плюс легкие альтернативы. **Бюджет app size ≤ 500 MB** для скачиваемых моделей.

**Apple system stack (0 MB — system-managed):**

| Модель | iOS | Заметки |
|---|---|---|
| SFSpeechRecognizer | 13+ | Legacy on-device API, baseline universal coverage |
| DictationTranscriber | 26+ | Fallback class в SpeechAnalyzer — "same devices as SFSpeechRecognizer" (включая 13 mini) |
| **SpeechTranscriber** ⭐ | 26+ | Apple's new model (iOS 26), powers Notes/Voice Memos/Journal. Designed for long-form + distant + noisy audio. System-managed via AssetInventory, auto-updated, не считается в app size. Likely supported на iPhone 13+ (per Fora Soft 2026 guide). **Главный candidate на default v0.1** |

**Open-source on-device (под бюджет 500 MB):**

| Модель | Размер | Источник | Заметки |
|---|---|---|---|
| WhisperKit base | ~150 MB | Argmax Swift package | Open-source baseline, проверенный |
| WhisperKit small | ~480 MB | Argmax Swift package | "iPhone 13 default" per Fora Soft. Recommended для нашего устройства |
| ~~WhisperKit large-v3-turbo~~ | 1.6 GB | — | Skip: за бюджетом + RAM tight на 4GB |

**Опциональные альтернативы (если стандартные слабы по Term Accuracy):**

| Модель | Размер | Источник | Заметки |
|---|---|---|---|
| Whisper.cpp iOS | 150-500 MB | github.com/ggerganov/whisper.cpp + Swift wrapper | Альтернативная implementation, может иметь другие traits (cold start, streaming) |
| Sherpa-onnx Whisper / Paraformer | ~200-500 MB | k2-fsa/sherpa-onnx | ONNX runtime, multilingual, иногда лучше на русском |
| Vosk Russian small | ~50 MB | alphacephei.com/vosk | Ultra-light, Kaldi-based (не neural). Качество хуже Whisper, но если нужна fallback при minimal RAM |

**Что НЕ в скоупе v0.1 (но в backlog):**
- **Gemma 3n E2B audio на iPhone** — MediaPipe iOS sample "coming soon" для Gemma 3n, MLX-Swift audio modality не подтверждён working на A15. Если в v0.2-0.3 Sergey сменит iPhone — пересмотрим
- **Apple Foundation Models (3B on-device LLM)** — требует Apple Intelligence device. Future consideration для intent classification поверх STT, если устройство обновится

---

## Корпус для записи

**4 пары текстов, 8 уникальных транскриптов.** Каждый текст — два уровня (5s ≈ 13-15 слов, 15s ≈ 40-45 слов). Цель — покрыть spectrum от чистой русской речи до англицизм-heavy dev команд.

### Set 1 — чистая русская речь (baseline)

**1A (5s):**
> Сегодня вторник, нужно успеть в магазин — купить молоко, хлеб, помидоры и заехать на заправку.

**1B (15s):**
> Сегодня вторник, к вечеру обещают дождь, поэтому нужно успеть в магазин, купить молоко, хлеб, помидоры, заехать на заправку, забрать сына с тренировки около семи и не забыть позвонить маме на обратной дороге.

### Set 2 — RU+EN dev-команды (main voice-assistant use case)

**2A (5s):**
> Запушь ветку feature auth в GitHub и открой pull request на ревью.

**2B (15s):**
> Запушь текущую ветку feature-auth в GitHub, открой pull request на main, добавь Сергея в ревьюверы, и проверь что прошли все CI чеки перед мёрджем — линт, юнит-тесты и тайп-чек.

### Set 3 — observability / incident triage

**3A (5s):**
> Открой дашборд api-latency в Grafana и покажи пятый процентиль.

**3B (15s):**
> Открой дашборд api-latency в Grafana за последний час, посмотри есть ли всплески по пятому процентилю, если есть — открой логи пода auth-service в staging кластере и пришли мне трейс ошибки.

### Set 4 — версии, числа, аббревиатуры (STT edge case)

**4A (5s):**
> Обнови WhisperKit до версии ноль точка восемь точка три.

**4B (15s):**
> В Package.swift обнови WhisperKit до версии ноль точка восемь точка три, перезапусти build через swift build, и если зелёный — закомить с сообщением update WhisperKit to zero dot eight dot three.

---

## Environment matrix

8 транскриптов × 4 audio variants = **32 файла для STT прогона**. Sergey записывает 16 originals на iPhone, ffmpeg на VDS генерирует 16 derived.

| Variant | Формат | Источник |
|---|---|---|
| `quiet-clean` | 16kHz mono float32 WAV (после normalize) | iPhone Voice Memos дома |
| `noisy-clean` | 16kHz mono float32 WAV | iPhone Voice Memos на улице (городской шум, машины) |
| `quiet-amrnb` | AMR-NB encoded → decoded back to 16kHz WAV | `scripts/derive-gsm.sh` из `quiet-clean` |
| `noisy-amrnb` | AMR-NB encoded → decoded back to 16kHz WAV | `scripts/derive-gsm.sh` из `noisy-clean` |

**Почему AMR-NB:** в реальной GSM voice cell (HYP-045 scenario — звонящий через USB GSM модем) используется AMR-NB кодек 4.75-12.2 kbps на 8kHz sample rate. Это режет всю информацию выше 4kHz (Nyquist) — а это именно те частоты, где сидят consonants (/s/, /sh/, /f/, /t/), особенно в англицизмах. Эмуляция через ffmpeg `libopencore_amrnb` даёт реалистичный worst-case.

**Bitrate 12.2 kbps** (max AMR-NB profile) — best case. Если результаты на 12.2 терпимы, можно опционально прогнать 4.75 kbps как stress test.

**AMR-WB (HD voice / VoLTE):** не добавляем в базовый прогон. Если AMR-NB убивает WER > 15% — отдельно проверим AMR-WB как вариант "если modem поддерживает VoLTE".

### Naming convention

```
assets/bench/raw/         # iPhone exports (.m4a)
  ├── 1a-quiet.m4a
  ├── 1a-noisy.m4a
  ├── 1b-quiet.m4a
  ├── 1b-noisy.m4a
  └── ... (16 файлов)

assets/bench/normalized/  # 16kHz mono float32 WAV (clean variants)
  ├── 1a-quiet.wav
  ├── 1a-noisy.wav
  └── ... (16 файлов)

assets/bench/amrnb/       # AMR-NB derived
  ├── 1a-quiet.wav        # содержит amrnb-degraded audio в 16kHz контейнере
  ├── 1a-noisy.wav
  └── ... (16 файлов)
```

`assets/` в `.gitignore` — не пушим аудио в публичный репо.

---

## Ground truth

`assets/bench/ground-truth.json`:

```json
{
  "1a": {
    "transcript": "Сегодня вторник, нужно успеть в магазин — купить молоко, хлеб, помидоры и заехать на заправку.",
    "duration_target_s": 5,
    "anglicisms": [],
    "category": "clean-russian"
  },
  "2a": {
    "transcript": "Запушь ветку feature auth в GitHub и открой pull request на ревью.",
    "duration_target_s": 5,
    "anglicisms": ["feature", "auth", "GitHub", "pull request"],
    "category": "ru-en-mix"
  },
  "...": "..."
}
```

**Список англицизмов per текст** — критично для Term Accuracy metric. Считаем правильно распознанные термины из списка против раскрытого транскрипта (после Unicode normalize + lowercase). Учитываем варианты: `GitHub` ≈ `гитхаб` ≈ `git hub` — это всё correct (для нашего use case любая форма пишется в текст, который потом injected в Claude).

---

## Метрики

8 метрик из HYP-028 + 2 voice-specific:

| Метрика | Что измеряет | Способ |
|---|---|---|
| **RTF** | Real-time factor: wall-clock / audio length | хорошо <1.0 (быстрее реалтайма) |
| **WER** | Общая word error rate | `jiwer` Python, после text normalization |
| **Term Accuracy** ⭐ | Англицизмы правильно распознаны | ручной count vs список из ground-truth |
| **Punctuation F1** | Точки/запятые/знаки вопроса | F1 vs ground truth (важно для UX) |
| **Cold start latency** | Первый запрос (load model) | wall-clock |
| **Warm latency** | Медиана из 10 последовательных | wall-clock |
| **VRAM/Metal peak + avg** | Practical limit + steady-state | per-second log, peak/p95/avg |
| **GPU util %** | Насыщение GPU | `nvidia-smi --query-gpu=utilization.gpu` 1Hz / `powermetrics` |
| **GPU power (W)** | Energy footprint + throttling indicator | `nvidia-smi --query-gpu=power.draw` / `powermetrics` |
| **GPU temp (°C)** | Thermal throttling early warning | `nvidia-smi --query-gpu=temperature.gpu` |
| **CPU avg %** | Преднагрузка cores | `psutil.cpu_percent()` cross-platform |
| **RAM (RSS) peak** | Per-process memory | `psutil.Process(pid).memory_info().rss` |
| **Disk IO (cold start)** | Model load latency component | `psutil.disk_io_counters()` |
| **Intent accuracy** | Gemma audio: команду поняла правильно? | manual eval (только для Gemma end-to-end) |
| **ΔWER (clean → amrnb)** ⭐ | GSM band impact | per-text: `WER(amrnb) - WER(clean)` |
| **Noise robustness** | quiet vs noisy WER delta | per-text: `WER(noisy) - WER(quiet)` |

⭐ — voice-specific дополнения относительно HYP-028.

### Text normalization для WER scoring

Прежде чем считать WER:
1. Unicode NFC normalize
2. Lowercase
3. Strip punctuation (но Punctuation F1 считаем ДО этого шага)
4. Числа в digits: `ноль точка восемь` → `0.8`, `пятый` → `5й` или `5` (берём наиболее частую форму)
5. Англицизмы accept both forms: `GitHub` == `гитхаб` == `git hub`

`compute_metrics.py` имплементит эту нормализацию.

---

## Pipeline скриптов

```
bench/
├── scripts/
│   ├── derive-gsm.sh           # ffmpeg: clean → AMR-NB → decoded WAV
│   ├── normalize-raw.sh        # iPhone .m4a → 16kHz mono float32 WAV
│   ├── bench_whisper_faster.py # Win-home + Mac, faster-whisper API
│   ├── bench_whisper_cpp.sh    # Mac whisper.cpp CLI wrapper
│   ├── bench_gemma_audio.py    # Ollama API, audio→text/intent prompt
│   ├── bench_whisperkit.swift  # iPhone (delegate mac-home Claude)
│   ├── bench_apple_speech.swift# SFSpeechRecognizer (delegate mac-home)
│   ├── compute_metrics.py      # WER + Term Acc + ΔWER + RTF из results
│   └── run-all.sh              # Orchestrator
└── results/
    └── 2026-06-XX-bench.csv    # long-format: model × file × metric
```

Скрипты НЕ в `Sources/` (не идут в production binary), а в отдельной `bench/` папке, которая частично в gitignore (raw audio и CSV — нет, скрипты — да).

---

## Фазы (адаптация HYP-028)

### Phase 0 — подготовка корпуса (~2-3 часа)

- [ ] Sergey записывает 16 файлов на iPhone Voice Memos (quiet × 8 + noisy × 8)
- [ ] Экспорт через AirDrop → mac-home → scp на VDS
- [ ] `scripts/normalize-raw.sh` — m4a → 16kHz mono float32 WAV (на VDS)
- [ ] `scripts/derive-gsm.sh` — генерация 16 AMR-NB derived (на VDS)
- [ ] `assets/bench/ground-truth.json` — finalize транскрипты + англицизм-листы

### Phase 1 — установка stacks (~2 часа)

- [ ] Win-home SSH access verify, проверить free disk + CUDA toolkit
- [ ] Win-home: `pip install faster-whisper torch --index-url https://download.pytorch.org/whl/cu121`
- [ ] Win-home: Ollama install, попытаться `ollama pull gemma3n:e4b` (или `gemma4:e4b` если есть)
- [ ] mac-home: убедиться что whisper.cpp Metal работает (HYP-028 уже подтверждает что есть)
- [ ] mac-home: Ollama install, `ollama pull gemma3n:e4b` (Gemma 4 12B Unified — проверить доступность в Ollama, может быть только через MLX)
- [ ] Smoke test: один короткий файл через каждую модель

### Phase 2 — прогон (~3-4 часа)

- [ ] 32 файла × все модели × 3 повтора (для usual latency)
- [ ] Сбор результатов в CSV (long format)
- [ ] Ручной Term Accuracy review (Sergey слушает + смотрит 50 случаев)
- [ ] iPhone тесты (WhisperKit + Apple Speech) — отдаём mac-home Claude session

### Phase 3 — анализ + decisions (~2 часа)

- [ ] Свод таблицы: best per use-case (5s команда / 15s длинный / clean / amrnb)
- [ ] W3 decision: on-device или server-side
- [ ] HYP-045 go/no-go по ΔWER threshold (>15% = мёртв)
- [ ] Writeback в `myRep/_project-hub/`:
  - HYP-028 — `## [NEW 2026-06-XX] Bench results — Whisper vs Gemma vs Apple Speech`
  - HYP-045 — `## [NEW 2026-06-XX] GSM emulation feasibility numbers`

---

## Критерии успеха (что должны узнать)

После прогона должны ответить:

1. ✅/❌ **Apple SFSpeechRecognizer** на нашем корпусе близок к WhisperKit base по WER и Term Accuracy? (если да — берём default, ноль модель-management кода в v0.1)
2. ✅/❌ **Whisper Large-v3 CUDA на Win-home** существенно быстрее M1 Pro Metal? (определяет где живёт server-side STT)
3. ✅/❌ **Gemma 4 / 3n audio** на русском технической речи **лучше** Whisper Large-v3 по term accuracy? (если да — переход на end-to-end voice→intent имеет смысл)
4. ✅/❌ **WhisperKit base на iPhone** укладывается в ≤ 600ms на 5s команде? (DoD из VISION для on-device path)
5. ✅/❌ **ΔWER (clean → amrnb) < 15%** для command set (Set 2/3)? (HYP-045 go/no-go)
6. ✅/❌ **ΔWER (quiet → noisy) < 10%** для лучшей модели? (noise robustness для outdoor использования)

---

## Риски и митигации

| Риск | Митигация |
|---|---|
| 🔴 Gemma 4 12B audio не в Ollama на 2026-06 (model fresh) | Fallback на Gemma 3n E2B/E4B (officially in HF), они стабильны с июня 2025 |
| 🔴 WhisperKit large-v3-turbo не лезет на iPhone (RAM) | Тестируем base + small, large опционально; не блокер |
| 🟡 SFSpeechRecognizer requires user-facing app (не доступен через CLI) | Тесты делает mac-home Claude через built `bench_apple_speech.swift` в Xcode проекте; long-running |
| 🟡 Тепловой троттлинг RTX 3070 Laptop | Медленные runs последними, мониторим `nvidia-smi -l 5` |
| 🟡 AMR-NB 12.2 kbps может быть оптимистичной emulation | Опциональный second run на 4.75 kbps для stress test |
| ⚠️ Privacy: дневники не записываем (только командный корпус) | Категория «дневник» из HYP-028 — skip для voice v0.1 plan, остаётся в HYP-028 backlog |
| ⚠️ Voice Memos на iPhone пишет 44.1kHz AAC mono — НЕ float32 | `normalize-raw.sh` делает downsample + format convert, потеря качества минимальная (только rate change) |

---

## Связи

- **HYP-028** parent — методология, метрики, фазы; результаты пишем туда writeback'ом
- **HYP-045** — ΔWER (clean → amrnb) ответит на feasibility voice IVR через GSM
- **VISION.md / MVP.md** — W3 decision определит STT в v0.1 client
- **specs/backend-protocol.md** — если server-side win, добавляем `/v1/voice/audio` (multipart)
- **.claude/TESTING.md** — bench-скрипты не TDD-обязательны (research tools, не production code)

---

## Текущий статус

См. `.claude/TASKS.md` § W1-W3 для трекинга. Phase 0 в работе после согласования этого документа.
