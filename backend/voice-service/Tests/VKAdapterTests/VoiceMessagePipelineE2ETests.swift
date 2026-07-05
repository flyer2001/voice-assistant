import XCTest
@testable import VKAdapter

/// 8 E2E scenarios — see specs/vk-bot-mvp.md S-1..S-8.
final class VoiceMessagePipelineE2ETests: XCTestCase {

    // MARK: - fixtures

    private static let owner: Int64 = 1001
    private static let stranger: Int64 = 9999
    private static let peer: Int64 = 1001
    private static let cwd = "/root/projects/assistant"

    private func makeUpdate(
        msgId: Int64 = 1,
        fromId: Int64 = owner,
        text: String = "",
        audio: VKAudioMessage? = nil
    ) -> (VKUpdate, VKMessage) {
        let attachments: [VKAttachment]? = audio.map {
            [VKAttachment(type: "audio_message", audioMessage: $0)]
        }
        let msg = VKMessage(
            id: msgId, date: 0, peerId: Self.peer,
            fromId: fromId, text: text, attachments: attachments
        )
        let update = VKUpdate(type: "message_new", object: VKObject(message: msg), groupId: nil)
        return (update, msg)
    }

    private func audio(
        duration: Int = 10, link: String = "https://vk.cdn/x.ogg",
        transcript: String? = nil, state: String? = nil
    ) -> VKAudioMessage {
        VKAudioMessage(
            id: 555, ownerId: 1001, duration: duration,
            linkOgg: link, linkMp3: nil, accessKey: nil,
            transcript: transcript, transcriptState: state
        )
    }

    private func makeRecorder() -> Recorder { Recorder() }
    final class Recorder: @unchecked Sendable {
        var vkSends: [(Int64, String)] = []
        var injects: [(String, String)] = []
        var transcribed: [Data] = []
        var downloads: [String] = []
    }

    private func makePipeline(
        rec: Recorder,
        download: VoiceMessagePipeline.DownloadFn? = nil,
        transcribe: VoiceMessagePipeline.TranscribeFn? = nil,
        happyInject: VoiceMessagePipeline.HappyInjectFn? = nil,
        vkSend: VoiceMessagePipeline.VKSendFn? = nil,
        resolveTarget: VoiceMessagePipeline.ResolveTargetFn? = nil,
        storageDir: URL? = nil
    ) -> (VoiceMessagePipeline, AudioStorage) {
        let dir = storageDir
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("pipe-\(UUID().uuidString)")
        let storage = AudioStorage(
            rawDir: dir.appendingPathComponent("raw"),
            auditPath: dir.appendingPathComponent("audit.jsonl")
        )
        let pipe = VoiceMessagePipeline(
            targetCwd: Self.cwd,
            ownerIds: [Self.owner],
            maxDurationS: 60,
            download: download ?? { url in
                rec.downloads.append(url)
                return Data([0x4F, 0x67, 0x67, 0x53])
            },
            transcribe: transcribe ?? { bytes in
                rec.transcribed.append(bytes)
                return "whisper text"
            },
            happyInject: happyInject ?? { text, cwd in
                rec.injects.append((text, cwd))
                return "ack from assistant"
            },
            vkSend: vkSend ?? { peer, text in
                rec.vkSends.append((peer, text))
            },
            storage: storage,
            resolveTarget: resolveTarget
        )
        return (pipe, storage)
    }

    private func readAuditEntries(_ storage: AudioStorage) throws -> [AuditEntry] {
        let data = try Data(contentsOf: storage.auditPath)
        let dec = JSONDecoder()
        return data.split(separator: 0x0a)
            .compactMap { line -> AuditEntry? in
                try? dec.decode(AuditEntry.self, from: line)
            }
    }

    // MARK: - S-1 happy path, VK transcript=done

    func test_S1_vkTranscriptDone_skipsWhisper_echoes_injects_replies() async {
        let rec = makeRecorder()
        let (update, msg) = makeUpdate(
            audio: audio(transcript: "что у меня по cashflow", state: "done")
        )
        let (pipe, _) = makePipeline(rec: rec)

        await pipe.handle(update, message: msg)

        XCTAssertEqual(rec.transcribed.count, 0, "whisper skipped когда VK transcript done")
        XCTAssertEqual(rec.vkSends.count, 2, "echo + reply")
        XCTAssertEqual(rec.vkSends[0].1, "👂 услышал: «что у меня по cashflow»")
        XCTAssertEqual(rec.vkSends[1].1, "ack from assistant")
        XCTAssertEqual(rec.injects.count, 1)
        XCTAssertEqual(rec.injects[0].1, Self.cwd)
        XCTAssertTrue(rec.injects[0].0.contains("[voice from Sergey, src=vk-transcript, lang=ru]"))
        XCTAssertTrue(rec.injects[0].0.contains("что у меня по cashflow"))
    }

    // MARK: - S-2 happy path, Whisper fallback

    func test_S2_transcriptInProgress_usesWhisper_echoesAndInjects() async {
        let rec = makeRecorder()
        let (update, msg) = makeUpdate(
            audio: audio(transcript: "", state: "in_progress")
        )
        let (pipe, _) = makePipeline(rec: rec)

        await pipe.handle(update, message: msg)

        XCTAssertEqual(rec.transcribed.count, 1, "whisper вызван")
        XCTAssertEqual(rec.vkSends.count, 2)
        XCTAssertEqual(rec.vkSends[0].1, "👂 услышал: «whisper text»")
        XCTAssertTrue(rec.injects[0].0.contains("src=whisper"))
    }

    // MARK: - S-3 Whisper down

    func test_S3_whisperFails_sendsError_noInject() async {
        struct WErr: Error {}
        let rec = makeRecorder()
        let (update, msg) = makeUpdate(audio: audio())
        let (pipe, _) = makePipeline(
            rec: rec,
            transcribe: { _ in throw WErr() }
        )

        await pipe.handle(update, message: msg)

        XCTAssertEqual(rec.injects.count, 0)
        XCTAssertEqual(rec.vkSends.count, 1)
        XCTAssertTrue(rec.vkSends[0].1.contains("STT недоступен"))
    }

    // MARK: - S-4 Happy session not running

    func test_S4_happyNoSession_echoesThenError() async {
        struct InjectErr: Error, CustomStringConvertible {
            var description: String { "Error.state(.noRunningSessionForCwd(\"/x\"))" }
        }
        let rec = makeRecorder()
        let (update, msg) = makeUpdate(audio: audio(transcript: "тест", state: "done"))
        let (pipe, _) = makePipeline(
            rec: rec,
            happyInject: { _, _ in throw InjectErr() }
        )

        await pipe.handle(update, message: msg)

        XCTAssertEqual(rec.vkSends.count, 2, "echo прошёл + error notice")
        XCTAssertTrue(rec.vkSends[0].1.contains("👂"))
        XCTAssertTrue(rec.vkSends[1].1.contains("session offline"))
    }

    // MARK: - S-5 Happy reply timeout

    func test_S5_happyTimeout_sendsTimeoutNotice() async {
        struct TErr: Error, CustomStringConvertible {
            var description: String { "Error.waitTimeout" }
        }
        let rec = makeRecorder()
        let (update, msg) = makeUpdate(audio: audio(transcript: "x", state: "done"))
        let (pipe, _) = makePipeline(
            rec: rec,
            happyInject: { _, _ in throw TErr() }
        )

        await pipe.handle(update, message: msg)

        XCTAssertTrue(rec.vkSends.last!.1.contains("timeout"))
    }

    // MARK: - S-6 not-allowlisted user

    func test_S6_strangerDropped_noSideEffects() async {
        let rec = makeRecorder()
        let (update, msg) = makeUpdate(
            fromId: Self.stranger,
            audio: audio(transcript: "anything", state: "done")
        )
        let (pipe, _) = makePipeline(rec: rec)

        await pipe.handle(update, message: msg)

        XCTAssertEqual(rec.vkSends.count, 0)
        XCTAssertEqual(rec.injects.count, 0)
        XCTAssertEqual(rec.downloads.count, 0)
    }

    // MARK: - S-7 non-audio message

    func test_S7_textOnly_ignored() async {
        let rec = makeRecorder()
        let (update, msg) = makeUpdate(text: "просто текст", audio: nil)
        let (pipe, _) = makePipeline(rec: rec)

        await pipe.handle(update, message: msg)

        XCTAssertEqual(rec.vkSends.count, 0)
        XCTAssertEqual(rec.injects.count, 0)
    }

    // MARK: - S-8 audio > 60s

    func test_S8_audioTooLong_rejected() async {
        let rec = makeRecorder()
        let (update, msg) = makeUpdate(audio: audio(duration: 120))
        let (pipe, _) = makePipeline(rec: rec)

        await pipe.handle(update, message: msg)

        XCTAssertEqual(rec.injects.count, 0)
        XCTAssertEqual(rec.downloads.count, 0)
        XCTAssertEqual(rec.vkSends.count, 1)
        XCTAssertTrue(rec.vkSends[0].1.contains("> 60s"))
    }

    // MARK: - Phase 6 F2 — S9/S10/S11 focus routing

    func test_S9_focusValid_routesToFocusCwd_auditRecordsFocus() async throws {
        let rec = makeRecorder()
        let (update, msg) = makeUpdate(audio: audio(transcript: "поехали", state: "done"))
        let (pipe, storage) = makePipeline(
            rec: rec,
            resolveTarget: { ("/root/projects/cashflow", "focus") }
        )

        await pipe.handle(update, message: msg)

        XCTAssertEqual(rec.injects.count, 1)
        XCTAssertEqual(rec.injects[0].1, "/root/projects/cashflow", "inject routed to focus cwd, not default")

        let audits = try readAuditEntries(storage)
        XCTAssertEqual(audits.last?.targetCwd, "/root/projects/cashflow")
        XCTAssertEqual(audits.last?.focusSource, "focus")
    }

    func test_S10_focusOffline_fallbackToDefault_auditRecordsFallback() async throws {
        let rec = makeRecorder()
        let (update, msg) = makeUpdate(audio: audio(transcript: "тест", state: "done"))
        // Simulate FocusState.validate → .fallback("session_offline"): resolver
        // returns default cwd + fallback tag (this is exactly what the
        // production wire does for a stale focus).
        let (pipe, storage) = makePipeline(
            rec: rec,
            resolveTarget: { (Self.cwd, "fallback_session_offline") }
        )

        await pipe.handle(update, message: msg)

        XCTAssertEqual(rec.injects[0].1, Self.cwd, "fallback → default cwd")
        let audits = try readAuditEntries(storage)
        XCTAssertEqual(audits.last?.focusSource, "fallback_session_offline")
    }

    func test_S11_noResolver_defaultTargetCwd_focusSourceDefault() async throws {
        let rec = makeRecorder()
        let (update, msg) = makeUpdate(audio: audio(transcript: "по умолчанию", state: "done"))
        let (pipe, storage) = makePipeline(rec: rec)  // no resolveTarget

        await pipe.handle(update, message: msg)

        XCTAssertEqual(rec.injects[0].1, Self.cwd)
        let audits = try readAuditEntries(storage)
        XCTAssertEqual(audits.last?.targetCwd, Self.cwd)
        XCTAssertEqual(audits.last?.focusSource, "default")
    }
}
