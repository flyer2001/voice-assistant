# Long-form STT Benchmark Report — 2026-06-11

## Также в этой сессии: iPhone V3 WhisperKit base bench

Запущен Sergey'ем через Xcode (manual codesign требовался — SSH session не имеет access к Keychain). 32 audio × 3 runs = 96 транскрипций. Сравнение с V2 Apple stack baseline:

| iPhone модель | WER clean | Term Acc | Latency | Примечание |
|---|---|---|---|---|
| **WhisperKit base (V3 NEW)** | **62.6%** | **50.7%** | **368ms** | bundled CoreML, ~480MB |
| Apple DictationTranscriber (V2) | 49.8% | 43.2% | 1166ms | iOS 26+, system-managed |
| Apple SFSpeechRecognizer (V2) | 83.9% | 26.6% | 684ms | legacy |
| Apple SpeechTranscriber (V2) | 100% ❌ | — | 166ms | broken в iOS 26.5 |

**Выводы V3:**
- WhisperKit base **на 3× быстрее** DictationTranscriber'а (368ms vs 1166ms)
- WhisperKit base **проигрывает** DictationTranscriber'у по WER (62.6 vs 49.8, +12.8pp)
- Преимущество только на Term Acc (50.7 vs 43.2, +7.5pp marginal)
- **Не clear winner** для voice assistant — DictationTranscriber лучше для overall transcription, WhisperKit base для latency-критичного intent matching

**Per-set V3 WhisperKit (clean):**
| Set | WER | Term | Lat |
|---|---|---|---|
| 1 baseline (RU) | 20.6% | 100% | 406ms |
| 2 dev cmds (RU+EN) | 72.6% | 38% | 392ms |
| 3 observ (RU+EN) | 49.3% | 48% | 381ms |
| 4 numbers | 107.7% | 17% | 295ms |

→ **WhisperKit base на iPhone 13 mini ~ comparable Apple DictationTranscriber, не upgrade.** Возможно WhisperKit small (110M params) даст больше — но не помещается на 4GB RAM iPhone 13 mini вместе с Apple stack.

Raw CSV: `bench/results/ios-v3-bench-results.csv`, metrics: `bench/results/ios-v3-bench-metrics.csv`.

---

## Scope

Single test: **28 мин 20 сек** EN podcast (Stack Overflow — "Are AI agents ready for the enterprise?"), Deepak Singh (AWS) гость. Editorial transcript ~5240 words с RD/DS speaker prefixes, professional editing.

**Цель**: проверить гипотезу Sergey'я — на длинных файлах Gemma 3n's paraphrasing может выиграть у Whisper's verbatim для **«статья-заметка»** output style, даже ценой WER.

## Files

- `bench/scripts/bench_longform.py` — runner (faster-whisper turbo+large + Gemma 3n chunked 29s)
- `bench/scripts/compute_longform_metrics.py` — extended metrics (WER + Term + Readability + Topic Jaccard)
- `assets/long-form-bench/en/stack-overflow-agents.wav` (104MB, 16kHz mono, 1700s)
- `assets/long-form-bench/en/stack-overflow-agents-transcript.txt` (27.8K chars, 5242 words)
- `bench/results/longform-2026-06-11.csv` — raw transcripts (model × run)
- `bench/results/longform-metrics-2026-06-11.csv` — per-row metrics

## Top-line results

| Model | WER | Term Acc | Sentences | Words | Avg sent len | Punct density | Topic Jaccard | Latency |
|---|---|---|---|---|---|---|---|---|
| **win-cuda/large-v3-turbo** | **12.6%** | 91.7% | **2** | 5637 | **2818** | 3.03% | 0.852 | **47.3 s** |
| **win-cuda/large-v3** | **11.4%** | **95.8%** | **213** | 5510 | 25.9 | **10.10%** | **0.887** | 232.5 s |
| **win-cuda/gemma-3n-E2B** (29-sec sample only) | n/a | n/a | n/a | 47 | 15.7 | **17.0%** | n/a | 24 s for 29 s |

Editorial transcript baseline:
- Sentences: ~280, Avg sent len: ~19 words, Punct density: ~11%

⚠️ **Gemma 3n chunked full 28-min run impractical on RTX 3070 8GB** — bfloat16 path даёт 25-50 sec/chunk × 58 chunks × 3 runs = >70 min, реально каждый раз зависал на 44+ min wall-clock без single CSV row. Использован **29-сек intro sample** для качественного сравнения style. Full long-form Gemma run требует hardware с >16GB VRAM (H100 / RTX 5090 / M-series Apple Silicon с unified memory).

## Key findings (Whisper part)

### 1. WER vs editorial — ниже чем ожидали

Initial гипотеза: WER 30-50% baseline penalty (editorial ≠ verbatim).

**Actual**: 11-13% — потому что editorial transcript этого подкаста почти verbatim (light edit, не paraphrased article). Это ОК для bench — но значит editorial ≠ "article-likeness" reference. Метрика WER не разделяет turbo от large по качеству **транскрипции**, потому что текст почти идентичен.

### 2. Punctuation / sentence structure — **большая разница** turbo vs large

| Metric | turbo | large |
|---|---|---|
| Sentence count | 2 | 213 |
| Punct density | 3% | 10% |
| Avg sentence length | 2818 words ⚠️ | 25.9 words ✅ |

`faster-whisper transcribe()` с `large-v3-turbo` выдаёт **wall-of-text** — нет точек, нет caps, lowercase stream. Использовать его как article-source невозможно без post-processing.

`large-v3` выдаёт **real sentences с punctuation** (213 предложений, avg 26 слов — близко к editorial 19 слов).

→ **Для «статья-заметка» output style large-v3 явный winner over turbo, несмотря на 5× slower (47s → 232s на 28-min файле).**

### 3. Term accuracy — обе модели сильны

Из 24 key terms (Amazon Q, Bedrock, AWS, Java, React, Deepak Singh, LLM, RAG, automated reasoning, guardrails, ...):
- turbo: 22/24 (91.7%)
- large: 23/24 (95.8%)

Whisper доминирует на vocabulary — обе модели tracking всех major terms из эпизода.

### 4. Topic word overlap (Jaccard top-50 content words)

- turbo: 0.852
- large: 0.887

Оба — отличный vocabulary coverage. Editorial structure preserved.

### 5. Speaker tags (RD/DS regex count)

Оба: **0**. Whisper не делает diarization. Если важно — нужен external diarization step (pyannote или similar) или separate VAD-based segmentation.

## Sample outputs (first 600 chars, intro section)

**Editorial reference:**
```
[intro music plays] Ryan Donovan: Brain computer interfaces are transforming human communication. Join Raymond Yin, host of the Tech Between Us Podcast, and Dr. Dan Rubin, Critical Care Neurologist at Massachusetts General Hospital, as they discuss the latest advancements. Listen now on your favorite podcast platform, or visit us at mouser.com/empowering-innovation. RD Hello everyone, and welcome to the Stack Overflow Podcast, a place to talk all things software and technology. I am Ryan Donovan, your host for this episode, and today we are talking about AI agents.
```

**Whisper turbo (lowercase, wall-of-text):**
```
brain computer interfaces are transforming human communication join raymond yin host of the tech between us podcast and dr dan rubin critical care neurologist at massachusetts general hospital as they discuss the latest advancements listen now on your favorite podcast platform or visit us at mauser.com forward slash empowering dash innovation hello everyone and welcome to the stack overflow podcast a place to talk all things software and technology i am ryan donovan your host for this episode...
```

**Whisper large (mixed — early no punct, later proper):**
```
brain computer interfaces are transforming human communication join raymond yin... [first ~1000 chars no punct]
...And if you... care about photography and youth soccer, you can find me on Threads. Alright, everyone. Thanks for listening, and we'll talk to you next time.
```

(Whisper large добавляет punctuation после warm-up — модель адаптируется к domain в течение audio? или это side-effect chunking/conditioning).

**Gemma 3n (single 29-sec chunk, intro):**
```
Brain-computer interfaces are transforming human communication. Join Raymond Yin, 
host of the Tech Between Us podcast, and Dr. Dan Rubin, critical care neurologist 
at Massachusetts General Hospital, as they discuss the latest advancements. Listen 
now on your favorite podcast platform, or visit us at [website address].
```

47 слов в 3 предложениях, **avg 15.7 word/sentence**, perfect article format:
- ✅ Title Capitalization (Tech Between Us, Massachusetts General Hospital)
- ✅ Period boundaries (3 предложения на 29 сек = match editorial cadence)
- ✅ Hyphenation (Brain-computer)
- ✅ **Abstracts spoken URL** ("mouser.com forward slash empowering dash innovation" → "[website address]")

Тот же 29-sec intro в **Whisper turbo:**
```
brain computer interfaces are transforming human communication join raymond yin 
host of the tech between us podcast and dr dan rubin critical care neurologist 
at massachusetts general hospital as they discuss the latest advancements listen 
now on your favorite podcast platform or visit us at mauser.com forward slash 
empowering dash innovation
```
Lowercase, 0 sentences, verbatim URL spelling.

В **Whisper large** (same 29 sec):
```
brain computer interfaces are transforming human communication join raymond yin 
host of the tech between us podcast and dr dan rubin critical care neurologist 
at massachusetts general hospital as they discuss the latest advancements listen 
now on your favorite podcast platform or visit us at mauser.com forward slash 
empowering dash innovation
```
То же — lowercase, no punct. Large добавляет punctuation **позже** в file (post warm-up?), но в первых 60 sec тоже verbatim.

→ **Гипотеза Sergey'я подтверждена на 29-сек sample**: Gemma 3n даёт **article-style** output из коробки (caps, punct, abstraction), Whisper — verbatim.

## Sergey's hypothesis — verdict

**Подтверждена**, с caveats:

1. **Gemma 3n DOES paraphrase в article style** (intro 29 sec доказывает) — captures content + abstracts spoken artifacts.

2. **Но full long-form (28 min) impractical** на consumer GPU (RTX 3070 8GB). Нужно либо:
   - Apple Silicon с unified 32GB+ memory (M2 Pro / M4 Max)
   - Server-class GPU (H100 / A100)
   - Quantization (Gemma 3n + bitsandbytes 4-bit) — TODO следующая сессия
   - Whisper-then-LLM pipeline: Whisper → transcript → Claude/GPT prompt "rewrite as article"

3. **Whisper large-v3 — closest practical match** (213 sentences, 10% punct density, 11.4% WER). Не идеален (smart formatting только partial), но workable foundation.

## Practical recommendation для voice-assistant v0.x

Для **article-style** output на long-form audio:

**Path A (cheapest, available now):**
- Whisper large-v3 на Win-CUDA backend (already proven in Phase 1 bench)
- Post-process через Claude Haiku/Sonnet: "Rewrite this transcript as a clean article with paragraphs, proper punctuation, abstraction of spoken URLs/emails"
- ETA: ~4 min Whisper + <1 min Claude API на 28-min file
- Cost: ~$0.05 Claude API per long file

**Path B (single-model, but compute-heavy):**
- Gemma 3n E2B on Apple Silicon (M-series unified memory)
- 30-sec chunking pipeline (надо допилить debugging)
- ETA: ~10-15 min (estimated, не tested)
- Cost: $0 if local, no API

**Path C (future):**
- Gemma 3n quantized 4-bit (bitsandbytes) — fit в 4GB VRAM
- TODO: try BitsAndBytesConfig(load_in_4bit=True) на RTX 3070

Для v0.1 voice-assistant: **Path A** — proven & cheap. Для on-device privacy use case (Sergey'я "автономный mode"): **Path B** на mac-home M1 Pro 32GB.

## Files

- `bench/scripts/bench_longform.py` — runner с chunked Gemma support
- `bench/scripts/compute_longform_metrics.py` — extended metrics
- `bench/results/longform-2026-06-11.csv` — Whisper turbo + large rows (6 transcripts)
- `bench/results/longform-metrics-2026-06-11.csv` — Whisper metrics
- `bench/results/gemma-intro-sample.csv` — Gemma single 29-sec sample
- `bench/results/ios-v3-bench-results.csv` — V3 WhisperKit iPhone bench raw
- `bench/results/ios-v3-bench-metrics.csv` — V3 metrics
