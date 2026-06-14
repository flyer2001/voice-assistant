import Foundation

/// Result of a single speech-to-text run. Returned by the `sttProvider`
/// closure on `Configuration` (mock impl for tests, real Whisper impl for
/// production). Mirrors the JSON shape of `POST /v1/voice/audio`.
public struct STTResult: Sendable, Equatable {
    public let text: String
    public let lang: String
    public let durationS: Double
    public let sttMs: Int
    public let sttEngine: String
    public let sttSource: String

    public init(
        text: String,
        lang: String = "ru",
        durationS: Double = 0,
        sttMs: Int = 0,
        sttEngine: String,
        sttSource: String
    ) {
        self.text = text
        self.lang = lang
        self.durationS = durationS
        self.sttMs = sttMs
        self.sttEngine = sttEngine
        self.sttSource = sttSource
    }
}

public typealias STTProvider = @Sendable (_ audioBytes: Data, _ clientId: String) async throws -> STTResult
