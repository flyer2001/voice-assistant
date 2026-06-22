import Foundation
import VoiceServiceCore

let env = ProcessInfo.processInfo.environment

let token = env["VOICE_BACKEND_TOKEN"] ?? {
    fatalError("VOICE_BACKEND_TOKEN not set in env")
}()

let host = env["VOICE_HOST"] ?? "127.0.0.1"
let port = Int(env["VOICE_PORT"] ?? "") ?? 8089

let plan: CompositionPlan
do {
    plan = try parsePlan(env: env)
} catch CompositionError.missingTargetCwd {
    fatalError("HAPPY_MODE=live requires VOICE_TARGET_CWD (e.g. /root/projects/cashflow)")
} catch CompositionError.unknownSttMode(let m) {
    fatalError("STT_MODE=\(m) not recognised — expected mock|live or unset")
} catch CompositionError.unknownHappyMode(let m) {
    fatalError("HAPPY_MODE=\(m) not recognised — expected echo|live or unset")
} catch {
    fatalError("unexpected composition error: \(error)")
}

let config = buildConfiguration(token: token, plan: plan)
let app = VoiceServiceApp.make(config: config, host: host, port: port)
try await app.runService()
