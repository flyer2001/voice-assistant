import Foundation
import Logging
import VoiceServiceCore
import VKAdapter

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

let baseConfig = buildConfiguration(token: token, plan: plan)
var vkSendForConfig: (@Sendable (_ peerId: Int64, _ text: String) async throws -> Void)? = nil

// ── VK voice bot — optional background loop ──────────────────────────
//
// Enabled via VK_BOT_ENABLED=true + /etc/vk-bot.env (token + group_id +
// owner_ids). See specs/vk-bot-mvp.md.

if env["VK_BOT_ENABLED"]?.lowercased() == "true" {
    let logger = Logger(label: "vk-bot")
    let vkConfig: VKConfig
    do { vkConfig = try VKConfig.fromEnvironment(env) } catch {
        fatalError("VK_BOT_ENABLED=true but config invalid: \(error)")
    }

    guard case .live(let targetCwd) = plan.happy else {
        fatalError("VK_BOT_ENABLED requires HAPPY_MODE=live (got \(plan.happy))")
    }
    let whisperURL: String
    switch plan.stt {
    case .live(let u): whisperURL = u
    default: fatalError("VK_BOT_ENABLED requires STT_MODE=live (got \(plan.stt))")
    }

    let http = LiveVKHTTPClient()
    let api = VKAPIClient(token: vkConfig.botToken, httpClient: http, logger: logger)
    let messenger = LiveHappyInjectMessenger()
    let storage = AudioStorage(
        rawDir: URL(fileURLWithPath: env["VOICE_AUDIO_STORAGE"] ?? "/var/lib/voice-bot/raw"),
        auditPath: URL(fileURLWithPath: env["VOICE_AUDIT_LOG"] ?? "/var/lib/voice-bot/audit.jsonl")
    )

    let maxAudioS = Int(env["VOICE_MAX_AUDIO_S"] ?? "") ?? 300

    let pipeline = VoiceMessagePipeline(
        targetCwd: targetCwd,
        ownerIds: Set(vkConfig.ownerIds.map { Int64($0) }),
        maxDurationS: maxAudioS,
        download: { url in
            try await http.send(method: "GET", url: url, headers: [:], body: nil)
        },
        transcribe: { bytes in
            let relay = WhisperHTTPRelay(baseURL: whisperURL)
            return try await relay.transcribe(audio: bytes).text
        },
        happyInject: { text, cwd in
            // Fire-and-forget: dispatcher session replies async via
            // POST /v1/vk/send. The bot's "reply" to VK is the ack below,
            // not the dispatcher's actual answer.
            try await messenger.injectNoWait(text: text, targetCwd: cwd)
            return "👍 принял, отвечу в отдельном сообщении"
        },
        vkSend: { peer, text in
            _ = try await api.sendMessage(peerId: peer, text: text)
        },
        storage: storage
    )

    vkSendForConfig = { peer, text in
        _ = try await api.sendMessage(peerId: peer, text: text)
    }

    Task.detached {
        await runVKLoop(api: api, http: http, config: vkConfig, pipeline: pipeline, logger: logger)
    }
    logger.info("VK bot loop started", metadata: [
        "group_id": .stringConvertible(vkConfig.groupId),
        "owner_ids": .string(vkConfig.ownerIds.sorted().map(String.init).joined(separator: ","))
    ])
}

let config = Configuration(
    token: baseConfig.token,
    replyProvider: baseConfig.replyProvider,
    sttProvider: baseConfig.sttProvider,
    vkSendProvider: vkSendForConfig,
    requestLogger: baseConfig.requestLogger,
    audioLimits: baseConfig.audioLimits
)
let app = VoiceServiceApp.make(config: config, host: host, port: port)
try await app.runService()


/// Long-poll forever. Refetches server on `failed:2|3`. Dispatches each
/// message_new in a child Task so slow downloads don't block polling.
func runVKLoop(
    api: VKAPIClient, http: any VKHTTPClient, config: VKConfig,
    pipeline: VoiceMessagePipeline, logger: Logger
) async {
    while !Task.isCancelled {
        let server: VKLongPollServer
        do { server = try await api.getLongPollServer(groupId: config.groupId) }
        catch {
            logger.error("getLongPollServer failed, retry in 5s", metadata: ["err": .string("\(error)")])
            try? await Task.sleep(for: .seconds(5))
            continue
        }
        let client = VKLongPollClient(server: server, httpClient: http)
        let parser = VKEventParser()

        loop: while !Task.isCancelled {
            let outcome: VKPollOutcome
            do { outcome = try await client.nextBatch() }
            catch {
                logger.error("longpoll batch failed, refetching server", metadata: ["err": .string("\(error)")])
                break loop
            }
            switch outcome {
            case .needsServerRefetch:
                break loop
            case .updates(let updates):
                for u in updates {
                    guard u.type == "message_new", let msg = u.object?.message else {
                        _ = parser.parse(u) // log-only side effect skipped
                        continue
                    }
                    Task { await pipeline.handle(u, message: msg) }
                }
            }
        }
    }
}
