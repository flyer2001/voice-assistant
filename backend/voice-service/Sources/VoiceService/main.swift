import Foundation
import VoiceServiceCore

let token = ProcessInfo.processInfo.environment["VOICE_BACKEND_TOKEN"] ?? {
    fatalError("VOICE_BACKEND_TOKEN not set in env")
}()

// CWD that voice intents route into. Single-project mapping for v0.1.
// Multi-project routing (intent-based) is v0.3.
let targetCwd = ProcessInfo.processInfo.environment["VOICE_TARGET_CWD"] ?? {
    fatalError("VOICE_TARGET_CWD not set (e.g. /root/projects/cashflow)")
}()

let messenger = LiveHappyInjectMessenger()
let replyProvider = messenger.makeReplyProvider(targetCwd: targetCwd, timeout: .seconds(15))

let logPath = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOICE_LOG_PATH"] ?? "/var/log/voice.jsonl")
let logger = RequestLogger(path: logPath)

let host = ProcessInfo.processInfo.environment["VOICE_HOST"] ?? "127.0.0.1"
let port = Int(ProcessInfo.processInfo.environment["VOICE_PORT"] ?? "") ?? 8089

let config = Configuration(token: token, replyProvider: replyProvider, requestLogger: logger)
let app = VoiceServiceApp.make(config: config, host: host, port: port)
try await app.runService()
