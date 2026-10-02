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

// ── Маршрутизация по фокусу — общая для VK и навыка Алисы ────────────
//
// Раньше жила внутри VK-блока. Вынесена наверх, когда появился второй
// голосовой канал: две копии одной логики разъехались бы на первой же правке.
let focusEnabled = (env["VOICE_FOCUS_ENABLED"] ?? "true").lowercased() == "true"
let focusState = FocusState(
    path: URL(fileURLWithPath: env["VOICE_FOCUS_PATH"] ?? "/var/lib/voice-bot/focus.json")
)
let happyState = HappyState(happyHome: HappyState.defaultHome)
try? focusState.initIfAbsent()

/// Куда направить реплику: в проект под фокусом либо к диспетчеру.
let resolveFocusTarget: @Sendable (String) -> (cwd: String, source: String) = { defaultCwd in
    guard focusEnabled else { return (defaultCwd, "default") }
    switch focusState.validate(try? focusState.read(), happyState: happyState) {
    case .focus(let cwd):     return (cwd, "focus")
    case .fallback(let why):  return (defaultCwd, "fallback_\(why)")
    }
}

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

    // Phase 6 F2 — маршрутизация по фокусу. Резолвер общий с навыком Алисы,
    // объявлен выше.
    let resolveTarget: VoiceMessagePipeline.ResolveTargetFn? = focusEnabled
        ? { @Sendable in resolveFocusTarget(targetCwd) }
        : nil

    // Phase 6 F3-lite — VK text slash commands to set/clear focus without
    // going through dispatcher. Sergey types `/focus myRep` in VK → next voice
    // routes to /root/projects/myRep. Full voice-command parsing = future F3.
    let slashHandler: VoiceMessagePipeline.SlashCommandFn = { @Sendable peerId, text in
        @Sendable func reply(_ msg: String) async {
            _ = try? await api.sendMessage(peerId: peerId, text: msg)
        }
        let parts = text.split(separator: " ", maxSplits: 1)
        let cmd = String(parts[0])
        let arg = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        switch cmd {
        case "/focus":
            if arg.isEmpty {
                let current = (try? focusState.read())?.cwd ?? "(none → dispatcher)"
                await reply("🎯 current focus: \(current)")
                return true
            }
            let cwd = "/root/projects/\(arg)"
            guard FileManager.default.fileExists(atPath: cwd) else {
                await reply("❌ нет проекта \(arg) в /root/projects/")
                return true
            }
            let now = ISO8601DateFormatter().string(from: Date())
            try? focusState.write(Focus(cwd: cwd, since: now, note: "vk /focus \(arg)"))
            await reply("✅ focus → \(arg)")
            return true
        case "/to_assistant", "/reset", "/exit":
            try? focusState.write(Focus())
            await reply("✅ focus reset → dispatcher (assistant)")
            return true
        case "/help":
            await reply("""
                commands:
                /focus <name> — route voice to /root/projects/<name>
                /focus — show current focus
                /to_assistant | /reset | /exit — clear focus → dispatcher
                """)
            return true
        default:
            await reply("❓ unknown: \(cmd). Try /help")
            return false
        }
    }

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
        storage: storage,
        resolveTarget: resolveTarget,
        slashCommand: slashHandler
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

// ── Навык Алисы — второй канал ввода ─────────────────────────────────
//
// Портативная колонка как микрофон: Яндекс распознаёт речь сам и шлёт нам
// готовый текст. Годится для коротких команд — управления микрофоном в API
// нет, пауза на размышление обрывает реплику. Подробности и ограничения:
// docs/alice-skill-input.md.
//
// Включается ALICE_PATH_SECRET. Без него маршрут не поднимается.
let aliceConfig: AliceConfig? = {
    guard let secret = env["ALICE_PATH_SECRET"], !secret.isEmpty else { return nil }
    guard case .live(let defaultCwd) = plan.happy else {
        FileHandle.standardError.write(
            Data("ALICE_PATH_SECRET задан, но HAPPY_MODE не live — навык отключён\n".utf8))
        return nil
    }
    let messenger = LiveHappyInjectMessenger()
    let logger = Logger(label: "alice")
    let peer = env["VK_BOT_OWNER_IDS"] ?? ""

    // Ящик ответа. Агент кладёт текст файлом, человек просит «дай ответ» —
    // навык озвучивает и опустошает. Так колонка отдаёт ответ голосом, хотя
    // заговорить первой не может. Одноразовость нарочная: иначе на второй
    // вопрос Алиса повторит прошлый ответ.
    let answerFile = URL(fileURLWithPath:
        env["ALICE_ANSWER_FILE"] ?? "/var/lib/voice-bot/alice-answer.txt")
    // Прочитанное живёт рядом: ящик не одноразовый, повтор нужен на случай
    // «не расслышал», но звучит с оговоркой.
    let readAnswerFile = answerFile.deletingPathExtension()
        .appendingPathExtension("read")
        .appendingPathExtension(answerFile.pathExtension)

    return AliceConfig(
        pathSecret: secret,
        skillId: env["ALICE_SKILL_ID"],
        inject: { text in
            let (cwd, source) = resolveFocusTarget(defaultCwd)
            // ALICE_TARGET_SID адресует конкретную сессию. Нужно, когда в
            // каталоге несколько живых сессий: выбор по cwd берёт самую свежую,
            // и на обкатке реплики падали в соседнюю (2026-10-02).
            let targetSid = env["ALICE_TARGET_SID"]
            // Провенанс как у VK: сессия должна понимать, откуда реплика и
            // куда отвечать. Колонка ответ не озвучит — навык не может
            // заговорить первым, поэтому ответ уходит обычными каналами.
            let header = [
                "[voice from Sergey, src=alice-station, lang=ru, peer=\(peer)]",
                "[reply голосом в колонку: положи текст в \(answerFile.path) — Sergey скажет «дай ответ», Алиса озвучит и ящик опустеет]",
                "[reply обычными каналами: voice-say / voice-reply-both <peer> \"<text>\"]",
                "[details: docs/alice-skill-input.md]",
                "",
                text
            ].joined(separator: "\n")
            do {
                try await messenger.injectNoWait(text: header, targetCwd: cwd, targetSid: targetSid)
                logger.info("реплика передана", metadata: [
                    "cwd": .string(cwd), "focus_source": .string(source),
                    "sid": .string(targetSid ?? "по cwd"),
                    "chars": .stringConvertible(text.count)
                ])
            } catch {
                // Отвечать уже поздно — Алиса получила «передал» секунду назад.
                logger.error("инжект не дошёл", metadata: [
                    "cwd": .string(cwd), "error": .string("\(error)")
                ])
            }
        },
        takeAnswer: {
            /// Непустое содержимое файла или nil.
            func read(_ url: URL) -> String? {
                guard let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }
                return text
            }

            // Свежий ответ всегда побеждает прочитанный: агент, положив новый
            // текст, вытесняет прошлый вместе с пометкой повтора.
            if let text = read(answerFile) {
                // Переезд в «прочитанное» вместо опустошения: человек мог не
                // расслышать и попросить снова.
                try? FileManager.default.removeItem(at: readAnswerFile)
                try? FileManager.default.moveItem(at: answerFile, to: readAnswerFile)
                logger.info("ответ озвучен", metadata: [
                    "chars": .stringConvertible(text.count)
                ])
                return AliceAnswer(text: text, isRepeat: false)
            }
            if let text = read(readAnswerFile) {
                logger.info("ответ озвучен повторно", metadata: [
                    "chars": .stringConvertible(text.count)
                ])
                return AliceAnswer(text: text, isRepeat: true)
            }
            logger.info("ящик ответа пуст", metadata: ["file": .string(answerFile.path)])
            return nil
        }
    )
}()

if aliceConfig != nil {
    FileHandle.standardError.write(Data("навык Алисы включён\n".utf8))
}

let config = Configuration(
    token: baseConfig.token,
    replyProvider: baseConfig.replyProvider,
    sttProvider: baseConfig.sttProvider,
    vkSendProvider: vkSendForConfig,
    requestLogger: baseConfig.requestLogger,
    audioLimits: baseConfig.audioLimits,
    alice: aliceConfig
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
