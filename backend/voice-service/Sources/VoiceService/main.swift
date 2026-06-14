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

if mode == "mock" {
    // Smoke / dev mode — no Happy session needed, no log file write.
    replyProvider = { req in "[mock reply] \(req.text)" }
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

let sttProvider: STTProvider? = mode == "mock"
    ? { bytes, clientId in
        STTResult(
            text: "[mock] echo \(bytes.count) bytes from \(clientId)",
            sttEngine: "mock",
            sttSource: "mock"
        )
    }
    : nil

let config = Configuration(
    token: token,
    replyProvider: replyProvider,
    sttProvider: sttProvider,
    requestLogger: logger
)
let app = VoiceServiceApp.make(config: config, host: host, port: port)
try await app.runService()
