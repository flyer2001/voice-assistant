import Foundation
import Speech
import AVFoundation
import os
import VoiceAssistant
import WhisperKit

private let log = Logger(subsystem: "com.voiceassistant.app.flyer2001", category: "bench")

/// Headless STT bench runner.
/// Autostarts on app launch (ContentView .onAppear). Writes CSV to Documents,
/// emits os_log lines visible via `xcrun devicectl device console show`.
///
/// V1 — Apple frameworks only (no network needed):
///   - SFSpeechRecognizer (iOS 13+, legacy)
///   - DictationTranscriber (iOS 26+, SpeechAnalyzer fallback class)
///   - SpeechTranscriber (iOS 26+, new SpeechAnalyzer model)
///
/// WhisperKit base/small — отдельно (V2), нужны pre-downloaded models в bundle
/// или прокси для HF Hub. На iPhone 13 mini iOS 26.5 — все 3 Apple candidates available.
@MainActor
final class BenchRunner: ObservableObject {
    @Published var isRunning = false
    @Published var log_ui = ""

    private let runsPerFile = 3
    private let language = "ru-RU"
    private var csvURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bench-results.csv")
    }

    func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        log.info("=== BENCH START === iOS \(ProcessInfo.processInfo.operatingSystemVersionString) device \(self.deviceModel())")
        await appendUI("=== BENCH START ===")
        await appendUI("iOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        await appendUI("Device: \(deviceModel())")

        // Auth Speech framework
        let status = await requestSpeechAuth()
        log.info("Speech auth status: \(status.rawValue)")
        await appendUI("Speech auth: \(status.rawValue) (3=authorized)")

        let files = bundleAudioFiles()
        log.info("Bundle audio files: \(files.count)")
        await appendUI("Files: \(files.count)")

        // Init CSV
        let header = "model,file,codec,run,text,latency_ms,error\n"
        try? header.write(to: csvURL, atomically: true, encoding: .utf8)
        log.info("CSV at: \(self.csvURL.path)")

        // V3 — WhisperKit base ONLY (Apple stack уже прогнан в V2 run, sergey'я iPhone 13 mini
        // 4GB RAM не тянет WhisperKit small + Apple stack одновременно — OOM crash).
        log.info("Loading WhisperKit base...")
        await appendUI("Loading WhisperKit base...")
        let wkBase = await loadWhisperKit(modelName: "openai_whisper-base")
        log.info("WhisperKit base loaded: \(wkBase != nil)")
        await appendUI("WhisperKit base: \(wkBase != nil ? "✓" : "✗")")

        let candidates: [(String, (URL) async throws -> String)] = {
            var c: [(String, (URL) async throws -> String)] = []
            if let wk = wkBase {
                c.append(("whisperkit-base", { url in try await self.transcribeWhisperKit(wk, url: url) }))
            }
            return c
        }()

        for (modelName, transcribeFn) in candidates {
            log.info("--- model: \(modelName) ---")
            await appendUI("\n--- \(modelName) ---")
            for url in files {
                for run in 1...runsPerFile {
                    let codec = inferCodec(from: url)
                    let filename = url.lastPathComponent

                    let t0 = Date()
                    var text = ""
                    var errMsg = ""
                    do {
                        text = try await transcribeFn(url)
                    } catch {
                        errMsg = "\(error)"
                        log.error("\(modelName) \(filename) run \(run): \(errMsg)")
                    }
                    let latencyMs = Date().timeIntervalSince(t0) * 1000

                    appendCSVRow(model: modelName, file: filename, codec: codec, run: run,
                                 text: text, latencyMs: latencyMs, error: errMsg)

                    let snippet = String(text.prefix(50))
                    log.info("[\(modelName) \(filename) r\(run)] \(Int(latencyMs))ms — \(snippet)")
                    await appendUI("[\(filename) r\(run)] \(Int(latencyMs))ms — \(snippet)")
                }
            }
        }

        log.info("=== BENCH DONE ===")
        await appendUI("\n=== DONE ===")
        await appendUI("CSV: \(csvURL.lastPathComponent)")
    }

    // MARK: - Audio enumeration

    private func bundleAudioFiles() -> [URL] {
        let files = BenchResources.allAudioFiles()

        if files.isEmpty, let resURL = BenchResources.audioBundle.resourceURL {
            let walker = FileManager.default.enumerator(at: resURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            log.info("DEBUG bundle.module resourceURL: \(resURL.path)")
            var count = 0
            while let item = walker?.nextObject() as? URL {
                log.info("  DEBUG bundle.module: \(item.lastPathComponent)")
                count += 1
                if count > 40 { break }
            }
        }

        return files
    }

    /// Filename-based codec detection: setup-resources.sh prepends "gsm-" to
    /// GSM-degraded WAVs so they don't collide with clean variants in bundle root.
    private func inferCodec(from url: URL) -> String {
        return url.lastPathComponent.hasPrefix("gsm-") ? "gsm" : "clean"
    }

    // MARK: - Speech auth

    private func requestSpeechAuth() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }

    // MARK: - SFSpeechRecognizer

    private func transcribeSFSpeech(_ url: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)) else {
            throw BenchError.unavailable("recognizer ru-RU")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw BenchError.unavailable("on-device not supported for ru-RU")
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                if resumed { return }
                if let error = error {
                    resumed = true
                    cont.resume(throwing: error)
                    return
                }
                guard let result = result, result.isFinal else { return }
                resumed = true
                cont.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }

    // MARK: - SpeechAnalyzer / SpeechTranscriber (iOS 26)

    @available(iOS 26.0, *)
    private func transcribeSpeechTranscriber(_ url: URL) async throws -> String {
        let transcriber = SpeechTranscriber(
            locale: Locale(identifier: language),
            preset: .transcription
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let audioFile = try AVAudioFile(forReading: url)
        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            finishAfterFile: true
        )

        var transcript = ""
        for try await result in transcriber.results {
            transcript += String(result.text.characters)
        }
        _ = analyzer  // keep strong reference until results done
        return transcript
    }

    // MARK: - WhisperKit (CoreML on Apple Neural Engine)

    /// Load WhisperKit pipeline from bundled CoreML model folder.
    /// Returns nil on failure (logged). With .copy("Resources/whisperkit") in Package.swift,
    /// the folder is preserved as `<bundle>/whisperkit/<modelName>/` with .mlmodelc subdirs.
    private func loadWhisperKit(modelName: String) async -> WhisperKit? {
        let bundle = BenchResources.audioBundle
        let modelURL = bundle.bundleURL
            .appendingPathComponent("whisperkit", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            log.error("WhisperKit \(modelName): folder not found at \(modelURL.path)")
            return nil
        }
        do {
            let config = WhisperKitConfig(modelFolder: modelURL.path)
            return try await WhisperKit(config)
        } catch {
            log.error("WhisperKit \(modelName) init failed: \(error)")
            return nil
        }
    }

    private func transcribeWhisperKit(_ whisperKit: WhisperKit, url: URL) async throws -> String {
        let opts = DecodingOptions(
            language: "ru",
            temperature: 0.0,
            sampleLength: 224,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await whisperKit.transcribe(
            audioPath: url.path,
            decodeOptions: opts
        )
        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @available(iOS 26.0, *)
    private func transcribeDictation(_ url: URL) async throws -> String {
        let transcriber = DictationTranscriber(
            locale: Locale(identifier: language),
            preset: .longDictation
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let audioFile = try AVAudioFile(forReading: url)
        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            finishAfterFile: true
        )

        var transcript = ""
        for try await result in transcriber.results {
            transcript += String(result.text.characters)
        }
        _ = analyzer  // keep strong reference until results done
        return transcript
    }

    // MARK: - CSV

    private func appendCSVRow(model: String, file: String, codec: String, run: Int,
                              text: String, latencyMs: Double, error: String) {
        let escapedText = text.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedErr = error.replacingOccurrences(of: "\"", with: "\"\"")
        let line = "\(model),\(file),\(codec),\(run),\"\(escapedText)\",\(Int(latencyMs)),\"\(escapedErr)\"\n"
        if let data = line.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: csvURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }

    // MARK: - Helpers

    private func deviceModel() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }

    @MainActor
    private func appendUI(_ s: String) async {
        log_ui += s + "\n"
    }
}

enum BenchError: Error, CustomStringConvertible {
    case unavailable(String)
    var description: String {
        switch self {
        case .unavailable(let reason): return "unavailable: \(reason)"
        }
    }
}
