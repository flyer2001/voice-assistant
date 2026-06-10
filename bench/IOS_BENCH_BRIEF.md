# iOS on-device STT bench — brief для mac-home Claude session

> Этот документ — instructions для **другой Claude session на mac-home**, которая будет запускать iOS-side бенчмарка. VDS-сессия владеет server-side частью (Whisper/Gemma на Win-home/mac-home через SSH), но Xcode + iPhone доступны только mac-home Claude'у.

## Контекст

Бенчмарк сравнивает STT-модели для voice-assistant v0.1. Подробный план — `docs/whisper-benchmark-plan.md`. Твоя часть — **on-device candidates на iPhone 13 mini (A15 Bionic, 4GB RAM, iOS 26+)**.

## Что нужно проверить

5 моделей (см. план для деталей):

1. **SFSpeechRecognizer** (legacy iOS 13+) — `import Speech`, `SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))` + `SFSpeechURLRecognitionRequest`. Принудительно on-device: `recognizer.supportsOnDeviceRecognition = true; request.requiresOnDeviceRecognition = true`.

2. **DictationTranscriber** (iOS 26+) — fallback class в SpeechAnalyzer. "Same devices as SFSpeechRecognizer" — гарантированно работает на 13 mini.

3. **SpeechTranscriber** ⭐ (iOS 26+) — Apple's new model, **главный кандидат на default v0.1**. Через SpeechAnalyzer API + AssetInventory для download модели. Documentation: https://developer.apple.com/videos/play/wwdc2025/277/

4. **WhisperKit base** (~150 MB) — Swift Package `argmaxinc/WhisperKit`, model name `"openai_whisper-base"`. CoreML + ANE.

5. **WhisperKit small** (~480 MB) — same package, model `"openai_whisper-small"`. Recommended для iPhone 13 per Fora Soft 2026 guide.

## Audio files

32 файла на VDS в `assets/bench/`. Перенос на mac-home через scp:

```bash
mkdir -p ~/voice-bench
scp -r vds:/root/projects/voice/assets/bench/normalized ~/voice-bench/
scp -r vds:/root/projects/voice/assets/bench/gsm ~/voice-bench/
```

Format: 16kHz mono float32 WAV. 16 normalized (clean) + 16 GSM 06.10 degraded.

Имена: `{1a,1b,2a,2b,3a,3b,4a,4b}-{quiet,noisy}.wav`. Транскрипты + англицизмы — в `bench/ground-truth.json` (тоже скачать с VDS).

## Output format

Каждая модель × файл × run → одна строка CSV в `bench/results/2026-06-XX-ios-<model>.csv`. Schema совпадает с server-side scripts (см. `bench/scripts/bench_whisper_faster.py`):

```csv
model,file,codec,run,text,latency_ms,ram_peak_mb,ram_avg_mb,cpu_avg_pct,cpu_peak_pct,model_load_ms,device
```

`codec` — `clean` для файлов из `normalized/`, `gsm` — из `gsm/`. `device` — `iphone-13-mini` или `simulator-iphone-13-mini`.

HW мониторинг на iOS — через `mach_thread_info()` + `Process.memoryUsage` (см. ProcessInfo + os.proc_info). RAM peak за время transcribe — главное что измерить.

## Harness structure

XCTest проект в `iOS/VoiceBenchTests/` (создать рядом с основным Xcode project). Тесты:

```swift
final class SpeechTranscriberBench: XCTestCase {
    func testAllFilesAllRuns() async throws {
        let audioFiles = loadBundleAudio()  // 32 files
        let runs = 3
        var results = [BenchRow]()

        let analyzer = try await SpeechAnalyzer(...)
        let transcriber = try await SpeechTranscriber(...)
        // Warmup on first file
        _ = try await transcribe(audioFiles[0])

        for file in audioFiles {
            for run in 1...runs {
                let t0 = ContinuousClock.now
                let monitor = HardwareMonitor.start()
                let text = try await transcribe(file)
                let latencyMs = (ContinuousClock.now - t0).milliseconds
                let metrics = monitor.stop()
                results.append(BenchRow(
                    model: "SpeechTranscriber",
                    file: file.lastPathComponent,
                    codec: file.path.contains("/gsm/") ? "gsm" : "clean",
                    run: run,
                    text: text,
                    latencyMs: latencyMs,
                    ramPeakMb: metrics.ramPeakMb,
                    ...
                ))
            }
        }
        try saveCSV(results, to: "ios-speechtranscriber.csv")
    }
}
```

Аналогично для других 4 моделей. WhisperKit через:

```swift
let whisperKit = try await WhisperKit(model: "openai_whisper-base")
let result = try await whisperKit.transcribe(audioPath: file.path, decodeOptions: .init(language: "ru"))
let text = result.first?.text ?? ""
```

## Запуск

На реальном **iPhone 13 mini** через `xcrun xctrace` или просто Run Tests в Xcode. Не на симуляторе — на симуляторе нет Neural Engine, latency не репрезентативен.

Если iPhone 13 mini недоступен — fallback на iOS симулятор, но это качество тестируем, не latency.

После прогона — `scp results/ios-*.csv vds:/root/projects/voice/bench/results/` чтобы VDS-сессия мерджила с server-side cyframi в compute_metrics.py.

## Что делает VDS-сессия параллельно

- Setup Win-home: faster-whisper CUDA + Gemma 3n/4 через HF Transformers + PyTorch CUDA
- Setup mac-home (через SSH): whisper.cpp Metal + Ollama для Gemma (если хочешь — можешь сама поставить, я через SSH не блокирую)
- Bench scripts: `bench_whisper_faster.py`, `bench_whisper_cpp.py`, `bench_gemma_hf.py`, `compute_metrics.py` — уже готовы в `bench/scripts/`

## Координация

Через repo. Когда что-то сделала — push в `main` с commit message типа `bench: ios SpeechTranscriber results`. Я pull'у и анализирую.

Если что-то не получается — добавь note в `bench/IOS_NOTES.md` (или открой issue на GitHub).

## Связь с задачей

- VISION / MVP — voice-assistant v0.1 STT decision (W3)
- HYP-028 (myRep/_project-hub) — parent benchmark plan
- HYP-045 — voice IVR (GSM-derived files отвечают на feasibility)
- Главный вопрос: **SpeechTranscriber vs WhisperKit base/small** — кто лучше на Set 2/3 (англицизмы)?
