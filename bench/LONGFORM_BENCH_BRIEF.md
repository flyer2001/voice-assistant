# Long-form bench — Phase 2 brief

Подготовка от 2026-06-11 (ночь). Сам бенч в **следующей сессии**.

## Цель

Sergey'я гипотеза: Gemma 3n E2B paraphrasing / interpretation = exactly то, что нужно для **«статья-заметка»** output (vs verbatim transcript). На длинных файлах (15-30 мин) это может проявиться:
- Whisper: точный verbatim → высокий WER против editorial transcript (5-15pp baseline penalty)
- Gemma: интерпретация → может уйти **в плюс** или **в катастрофу** (как мы видели на коротких файлах)

Test case — **editorial transcript** профессионально отредактирован (с ролями, cohesive text, причёсанная грамматика), не subtitles.

## Готовое prep (в `assets/long-form-bench/en/`)

### EN candidate ✅

- **Stack Overflow Podcast — "Are AI agents ready for the enterprise?"**
  - Гость: Deepak Singh, VP Developer Agents and Experiences at AWS
  - Topic: AI agents в software development — Amazon Q Developer, autonomous coding agents, guardrails
  - Длина: **28 мин 20 сек** (1700 сек) — в target range
  - Audio: `stack-overflow-agents.wav` (104 MB, 16kHz mono float32 ✓)
  - Audio raw: `stack-overflow-agents.mp3` (27 MB original)
  - Transcript: `stack-overflow-agents-transcript.txt` (28K chars, **5088 слов**, editorial format с RD/DS speaker prefixes)
  - Sample (intro): _"RD Hello everyone, and welcome to the Stack Overflow Podcast, a place to talk all things software and technology. I am Ryan Donovan, your host for this episode..."_

### RU candidate ❌ — yt-dlp blocked

- **Podlodka #417 — Swift** (https://www.youtube.com/watch?v=gbIEmzD9n7Q) — YouTube вернул 403 на video download. Causes:
  - Russian ISP блокировки на YouTube traffic
  - yt-dlp выкручен YouTube'ом (HTTP 400 на player API)
  - Auto-subtitles захотел (не editorial, in any case)

  **Alternative для следующей сессии:**
  - Try yt-dlp на mac-home через `claude-ufo` proxy (часто помогает с YouTube блоками)
  - Или другой RU источник:
    - **Habr статья** "по мотивам подкаста" (editorial form, без audio)
    - **WWDC RU translation** sessions (Apple official content)
    - **Tinkoff/Avito/Yandex tech conference** talks — если есть audio + editorial article
  - Если RU не получим — EN-only bench всё равно даёт answer.

## Bench plan (next session)

### Models

| Model | Platform | Constraint |
|---|---|---|
| `win-cuda/whisper-large-v3-turbo` | faster-whisper | no length limit, **primary candidate** |
| `win-cuda/whisper-large-v3` | faster-whisper | no length limit, best quality reference |
| `win-cuda/google/gemma-3n-E2B-it` | HF Transformers | ⚠️ **30-sec audio limit** — нужно chunking |

### Gemma 30s chunking pipeline (TODO)

Gemma 3n E2B обучена на ≤30 сек clips. На 28-min файле:
1. Split audio into **chunks по 30 сек** через ffmpeg (или librosa slicing).
2. Optional: overlap 2-3 сек между chunks для смягчения boundary artifacts.
3. Inference per chunk → text segment.
4. Concat segments → single transcript output.
5. Можно делать parallel на 2 GPU streams если хочется быстрее.

**Skeleton code:**

```python
def gemma_long_inference(audio_16k_float32, processor, model, chunk_sec=29, overlap_sec=1):
    sr = 16000
    chunk_samples = chunk_sec * sr
    step = (chunk_sec - overlap_sec) * sr
    out = []
    for start in range(0, len(audio_16k_float32), step):
        chunk = audio_16k_float32[start : start + chunk_samples]
        if len(chunk) < sr * 2:  # skip <2 sec tails
            break
        messages = [{
            "role": "user",
            "content": [
                {"type": "audio", "audio": chunk},
                {"type": "text", "text": "Transcribe the following speech in English."},
            ],
        }]
        inputs = processor.apply_chat_template(messages, add_generation_prompt=True,
                                                tokenize=True, return_dict=True,
                                                return_tensors="pt").to(model.device)
        input_len = inputs["input_ids"].shape[1]
        out_ids = model.generate(**inputs, max_new_tokens=200, do_sample=False)
        out.append(processor.decode(out_ids[0][input_len:], skip_special_tokens=True))
    return " ".join(out)
```

ETA Gemma на 28 мин файле: 56 chunks × ~3-5 sec inference (after model load) = **3-5 мин для one transcription**. Для 3 runs × 1 file = 10-15 мин.

ETA Whisper turbo на 28 мин: ~30-60 сек per inference (RTF 0.03 — 30× realtime). 3 runs = 1.5-3 мин.

### Metrics — beyond WER

WER против editorial transcript будет inflated (~30-50% для всех моделей baseline). Нам интересны **дополнительные** метрики:

| Метрика | Что | Как |
|---|---|---|
| **WER** | classical word error rate | jiwer.wer на normalized text |
| **Term Accuracy** | англицизмы/имена/термы (Amazon Q, Anthropic, GitLab, etc) | manual aliases list |
| **Readability score** | насколько output читается как статья | sentence count, avg sentence length, punctuation density |
| **Speaker tags preserved** | сохранилась ли структура с ролями (RD/DS) | regex count of pattern "[A-Z]{2,3} " or named entities |
| **Topic word overlap** | сохранены ли ключевые term'ы | Jaccard на top-50 content words |
| **Coherence score** (если есть time) | LLM judge: насколько output reads as article | Claude API: rate 1-10 |

### Output format

Save в `bench/results/REPORT-LONGFORM-2026-06-11.md` — separate report с:
- Sample transcripts (first 500 chars each model) side by side
- Metrics tables
- **Editorial review** — Sergey subjective evaluation of "how article-like" output is

### Next-session steps

1. Skim это `LONGFORM_BENCH_BRIEF.md`
2. RU: попробовать yt-dlp через `claude-ufo` proxy на mac-home, или найти другой RU candidate
3. Implement chunking pipeline для Gemma (skeleton выше)
4. Add `bench_longform.py` script — runs всех 3 models на one audio file → CSV row
5. Run на `assets/long-form-bench/en/stack-overflow-agents.wav`
6. (Optional) Run на RU когда найдём
7. Generate report + commit

## Files

```
assets/long-form-bench/
├── en/
│   ├── stack-overflow-agents.mp3                    (27 MB, raw)
│   ├── stack-overflow-agents.wav                    (104 MB, 16kHz mono float32 ✓)
│   └── stack-overflow-agents-transcript.txt         (28K chars, 5088 words, editorial)
└── ru/
    └── (TODO — yt-dlp YouTube blocked)
```

## Связь с предыдущей секцией

Short-form bench (32 audio × 12 models × 2 codecs) показал:
- Server: **Whisper large-v3-turbo** winner
- On-device: **Apple DictationTranscriber**
- HYP-045 GSM: ✅ для turbo, ❌ для Gemma 3n
- Gemma 3n E2B paraphrases — для verbatim STT хуже Whisper

Long-form bench проверит **flipside гипотезу**: может paraphrasing годится для **«статья-заметка»** output? Это **новый use case** voice-assistant — не транскрипция, а **summarization-like transcription**.
