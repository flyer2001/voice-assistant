import Foundation

/// What the `/v1/voice/audio` endpoint should be wired to. `.disabled` means
/// the endpoint returns 503 — useful when only `/v1/voice/intent` is in use.
public enum SttPlan: Equatable, Sendable {
    case disabled
    case mock
    case live(whisperURL: String)
}

/// What the `/v1/voice/intent` endpoint should do. `.echo` returns
/// `[echo reply] <text>` (smoke-friendly, no Happy state needed). `.live`
/// wires `LiveHappyInjectMessenger` against the given target cwd.
public enum HappyPlan: Equatable, Sendable {
    case echo
    case live(targetCwd: String)
}

public struct CompositionPlan: Equatable, Sendable {
    public let stt: SttPlan
    public let happy: HappyPlan
    public let logPath: String?

    public init(stt: SttPlan, happy: HappyPlan, logPath: String?) {
        self.stt = stt
        self.happy = happy
        self.logPath = logPath
    }
}

public enum CompositionError: Error, Equatable {
    case missingTargetCwd
    case unknownSttMode(String)
    case unknownHappyMode(String)
}

/// Default Whisper FastAPI endpoint (ubuntu-home dual-boot, CUDA RTX 3070).
/// Override via WHISPER_URL.
public let defaultWhisperURL = "http://192.168.88.13:8000"

/// Default JSONL audit log path (matches systemd unit + deploy README).
public let defaultLogPath = "/var/log/voice.jsonl"

/// Parse environment into independent STT and Happy plans.
///
/// Defaults:
/// - `STT_MODE` unset → STT endpoint disabled (503).
/// - `HAPPY_MODE` unset, `VOICE_TARGET_CWD` unset → echo stub (safe).
/// - `HAPPY_MODE` unset, `VOICE_TARGET_CWD` set → live Happy inject (backwards compat with existing /etc/voice-backend.env).
///
/// Explicit `HAPPY_MODE` always wins over implicit cwd-based default.
public func parsePlan(env: [String: String]) throws -> CompositionPlan {
    let stt: SttPlan
    switch env["STT_MODE"] {
    case .none, "":
        stt = .disabled
    case "mock":
        stt = .mock
    case "live":
        stt = .live(whisperURL: env["WHISPER_URL"] ?? defaultWhisperURL)
    case .some(let other):
        throw CompositionError.unknownSttMode(other)
    }

    let happy: HappyPlan
    let cwd = env["VOICE_TARGET_CWD"]
    switch env["HAPPY_MODE"] {
    case .none, "":
        if let cwd, !cwd.isEmpty {
            happy = .live(targetCwd: cwd)
        } else {
            happy = .echo
        }
    case "echo":
        happy = .echo
    case "live":
        guard let cwd, !cwd.isEmpty else {
            throw CompositionError.missingTargetCwd
        }
        happy = .live(targetCwd: cwd)
    case .some(let other):
        throw CompositionError.unknownHappyMode(other)
    }

    let logPath = env["VOICE_LOG_PATH"] ?? defaultLogPath
    return CompositionPlan(stt: stt, happy: happy, logPath: logPath)
}

/// Build runtime `Configuration` from a plan + bearer token. STT/Happy
/// providers are constructed once and re-used per request.
public func buildConfiguration(token: String, plan: CompositionPlan) -> Configuration {
    let sttProvider: STTProvider?
    switch plan.stt {
    case .disabled:
        sttProvider = nil
    case .mock:
        sttProvider = { bytes, clientId in
            STTResult(
                text: "[mock] echo \(bytes.count) bytes from \(clientId)",
                sttEngine: "mock",
                sttSource: "mock"
            )
        }
    case .live(let url):
        sttProvider = { bytes, _ in
            let relay = WhisperHTTPRelay(baseURL: url)
            return try await relay.transcribe(audio: bytes)
        }
    }

    let replyProvider: @Sendable (IntentRequest) async throws -> String
    switch plan.happy {
    case .echo:
        replyProvider = { req in "[echo reply] \(req.text)" }
    case .live(let cwd):
        let messenger = LiveHappyInjectMessenger()
        replyProvider = messenger.makeReplyProvider(targetCwd: cwd, timeout: .seconds(15))
    }

    let logger: RequestLogger? = plan.logPath.map { RequestLogger(path: URL(fileURLWithPath: $0)) }

    return Configuration(
        token: token,
        replyProvider: replyProvider,
        sttProvider: sttProvider,
        requestLogger: logger
    )
}
