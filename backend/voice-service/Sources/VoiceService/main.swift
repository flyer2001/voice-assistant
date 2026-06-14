import Foundation
import VoiceServiceCore

let env = ProcessInfo.processInfo.environment
let token = env["VOICE_BACKEND_TOKEN"] ?? {
    fatalError("VOICE_BACKEND_TOKEN not set in env")
}()

let mode = env["STT_MODE"]                 // "mock" → echo audio bytes; otherwise nil
let host = env["VOICE_HOST"] ?? "127.0.0.1"
let port = Int(env["VOICE_PORT"] ?? "") ?? 8089

let replyProvider: @Sendable (IntentRequest) async throws -> String
let logger: RequestLogger?

// mock / live = STT-focused smoke modes; replyProvider is a stub since the
// /v1/voice/intent path isn't exercised. Production (no STT_MODE) wires the
// real Happy inject messenger.
if mode == "mock" || mode == "live" {
    replyProvider = { req in "[\(mode!) reply] \(req.text)" }
    logger = nil
} else {
    let targetCwd = env["VOICE_TARGET_CWD"] ?? {
        fatalError("VOICE_TARGET_CWD not set (e.g. /root/projects/cashflow)")
    }()
    let messenger = LiveHappyInjectMessenger()
    replyProvider = messenger.makeReplyProvider(targetCwd: targetCwd, timeout: .seconds(15))
    let logPath = URL(fileURLWithPath: env["VOICE_LOG_PATH"] ?? "/var/log/voice.jsonl")
    logger = RequestLogger(path: logPath)
}

let sttProvider: STTProvider?
switch mode {
case "mock":
    sttProvider = { bytes, clientId in
        STTResult(
            text: "[mock] echo \(bytes.count) bytes from \(clientId)",
            sttEngine: "mock",
            sttSource: "mock"
        )
    }
case "live":
    let urlStr = env["WHISPER_URL"] ?? "http://192.168.88.13:8000"
    sttProvider = { bytes, _ in
        let relay = WhisperHTTPRelay(baseURL: urlStr)
        return try await relay.transcribe(audio: bytes)
    }
default:
    sttProvider = nil
}

let config = Configuration(
    token: token,
    replyProvider: replyProvider,
    sttProvider: sttProvider,
    requestLogger: logger
)
let app = VoiceServiceApp.make(config: config, host: host, port: port)
try await app.runService()
