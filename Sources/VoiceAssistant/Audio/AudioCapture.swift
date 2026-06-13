import Foundation
import AVFoundation

public protocol AudioCapture: AnyObject, Sendable {
    /// Begin recording. Throws on permission denial or AVAudioEngine setup error.
    func start() async throws

    /// Stop recording. Returns URL of the captured audio file.
    /// Caller owns the file (delete after upload / playback).
    func stop() async throws -> URL
}

public enum AudioCaptureError: Error, Equatable {
    case permissionDenied
    case noActiveRecording
    case engineSetupFailed(String)
}

@MainActor
public final class LiveAudioCapture: AudioCapture {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public func start() async throws {
        try await ensurePermission()
        try configureSession()

        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)

        let url = makeFileURL()
        // Write in source (hardware-native) format. Conversion to 16 kHz mono
        // Float32 happens at upload time — keeps capture path simple and
        // avoids real-time AVAudioConverter complications. Whisper accepts
        // arbitrary sample rates with mild quality loss.
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: url, settings: sourceFormat.settings)
        } catch {
            throw AudioCaptureError.engineSetupFailed("AVAudioFile create: \(error.localizedDescription)")
        }
        self.audioFile = file
        self.currentURL = url

        input.installTap(onBus: 0, bufferSize: 4096, format: sourceFormat) { [weak self] buffer, _ in
            guard let file = self?.audioFile else { return }
            try? file.write(from: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            audioFile = nil
            currentURL = nil
            throw AudioCaptureError.engineSetupFailed("engine.start: \(error.localizedDescription)")
        }
    }

    public func stop() async throws -> URL {
        guard let url = currentURL else {
            throw AudioCaptureError.noActiveRecording
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        audioFile = nil
        currentURL = nil
        return url
    }

    private func ensurePermission() async throws {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:
            return
        case .denied:
            throw AudioCaptureError.permissionDenied
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted { throw AudioCaptureError.permissionDenied }
        @unknown default:
            throw AudioCaptureError.permissionDenied
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            throw AudioCaptureError.engineSetupFailed("AVAudioSession: \(error.localizedDescription)")
        }
    }

    private func makeFileURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent("recording-\(stamp).caf")
    }
}

#if DEBUG
@MainActor
public final class MockAudioCapture: AudioCapture {
    public private(set) var startCalls = 0
    public private(set) var stopCalls = 0
    public var failOnStart: AudioCaptureError?
    public var fixedURL = URL(fileURLWithPath: "/tmp/mock-recording.caf")

    public init() {}

    public func start() async throws {
        startCalls += 1
        if let err = failOnStart { throw err }
    }

    public func stop() async throws -> URL {
        stopCalls += 1
        return fixedURL
    }
}
#endif
