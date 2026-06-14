import Foundation

/// Backend configuration. `token` is the static Bearer accepted on the
/// Authorization header. `replyProvider` produces the assistant reply for
/// a given intent request — in tests it's a stub closure, in production
/// it will forward to Happy inject (port of inject.mjs, see Tasks B4-B5).
public struct Configuration: Sendable {
    public let token: String
    public let replyProvider: @Sendable (IntentRequest) async throws -> String
    public let sttProvider: STTProvider?
    public let requestLogger: RequestLogger?
    public let audioLimits: AudioLimits

    public init(
        token: String,
        replyProvider: @escaping @Sendable (IntentRequest) async throws -> String,
        sttProvider: STTProvider? = nil,
        requestLogger: RequestLogger? = nil,
        audioLimits: AudioLimits = .default
    ) {
        self.token = token
        self.replyProvider = replyProvider
        self.sttProvider = sttProvider
        self.requestLogger = requestLogger
        self.audioLimits = audioLimits
    }
}

/// Server-side audio constraints for POST /v1/voice/audio. Production
/// defaults rejct silent/empty uploads and impose a 32 MB body cap (≈5 min
/// at 16 kHz mono Int16). `lenient` is a test helper that disables all
/// checks so unit tests can use synthetic 16-byte payloads.
public struct AudioLimits: Sendable {
    public let minAudioBytes: Int
    public let maxAudioBytes: Int
    public let maxDeclaredDurationS: Double

    public init(minAudioBytes: Int, maxAudioBytes: Int, maxDeclaredDurationS: Double) {
        self.minAudioBytes = minAudioBytes
        self.maxAudioBytes = maxAudioBytes
        self.maxDeclaredDurationS = maxDeclaredDurationS
    }

    public static let `default` = AudioLimits(
        minAudioBytes: 1024,
        maxAudioBytes: 32 * 1024 * 1024,
        maxDeclaredDurationS: 60
    )

    public static let lenient = AudioLimits(
        minAudioBytes: 0,
        maxAudioBytes: .max,
        maxDeclaredDurationS: .infinity
    )
}
