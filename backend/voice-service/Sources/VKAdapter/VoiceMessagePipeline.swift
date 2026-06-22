import Foundation

/// Orchestrates VK voice message → Whisper/VK transcript → echo + Happy inject → reply.
/// Все depencies injected как closures — нет module coupling, мокается closures.
/// См. specs/vk-bot-mvp.md — 8 сценариев S-1..S-8.
public struct VoiceMessagePipeline: Sendable {

    public typealias DownloadFn = @Sendable (_ url: String) async throws -> Data
    public typealias TranscribeFn = @Sendable (_ audio: Data) async throws -> String
    public typealias HappyInjectFn = @Sendable (_ text: String, _ targetCwd: String) async throws -> String
    public typealias VKSendFn = @Sendable (_ peerId: Int64, _ text: String) async throws -> Void

    public let targetCwd: String
    public let ownerIds: Set<Int64>
    public let maxDurationS: Int
    public let download: DownloadFn
    public let transcribe: TranscribeFn
    public let happyInject: HappyInjectFn
    public let vkSend: VKSendFn
    public let storage: AudioStorage
    public let clock: @Sendable () -> Date

    public init(
        targetCwd: String,
        ownerIds: Set<Int64>,
        maxDurationS: Int = 60,
        download: @escaping DownloadFn,
        transcribe: @escaping TranscribeFn,
        happyInject: @escaping HappyInjectFn,
        vkSend: @escaping VKSendFn,
        storage: AudioStorage,
        clock: @Sendable @escaping () -> Date = { .now }
    ) {
        self.targetCwd = targetCwd
        self.ownerIds = ownerIds
        self.maxDurationS = maxDurationS
        self.download = download
        self.transcribe = transcribe
        self.happyInject = happyInject
        self.vkSend = vkSend
        self.storage = storage
        self.clock = clock
    }

    /// Handle one parsed event. Errors logged via audit, не пробрасываются —
    /// VK Long Poll loop должен продолжать работать.
    public func handle(_ update: VKUpdate, message: VKMessage) async {
        let started = clock()
        let msgId = message.id
        let peerId = message.peerId
        let fromId = message.fromId

        // S-6: not-allowlisted user → drop silently.
        guard ownerIds.contains(fromId) else {
            audit(decision: "drop_not_allowlisted", outcome: "dropped",
                  msgId: msgId, peerId: peerId, totalMs: ms(since: started))
            return
        }

        // S-7: non-audio message → ignore.
        guard let audio = message.attachments?.compactMap({ $0.audioMessage }).first else {
            audit(decision: "drop_not_audio", outcome: "dropped",
                  msgId: msgId, peerId: peerId, totalMs: ms(since: started))
            return
        }

        // S-8: too long → reject.
        if audio.duration > maxDurationS {
            try? await vkSend(peerId, "⚠️ audio > \(maxDurationS)s — обрежь или несколькими сообщениями.")
            audit(decision: "drop_too_long", outcome: "dropped",
                  msgId: msgId, peerId: peerId, durationS: audio.duration,
                  totalMs: ms(since: started))
            return
        }

        // Download .ogg + save raw.
        let audioBytes: Data
        let audioPath: URL?
        do {
            audioBytes = try await download(audio.linkOgg)
            audioPath = try storage.saveAudio(audioBytes, msgId: msgId, ts: clock())
        } catch {
            try? await vkSend(peerId, "⚠️ не смог скачать audio: \(error)")
            audit(decision: "error_download", outcome: "error",
                  msgId: msgId, peerId: peerId, durationS: audio.duration,
                  totalMs: ms(since: started))
            return
        }

        // Decide transcript source.
        let decision = TranscriptDecider.decide(
            transcript: audio.transcript, transcriptState: audio.transcriptState
        )
        let transcriptText: String
        let sttMs: Int
        let transcriptVk: String?
        let transcriptWhisper: String?
        let decisionTag: String

        switch decision {
        case .useVK(let vkText):
            transcriptText = vkText
            sttMs = 0
            transcriptVk = vkText
            transcriptWhisper = nil
            decisionTag = "used_vk"

        case .useWhisper:
            let sttStart = clock()
            do {
                transcriptText = try await transcribe(audioBytes)
            } catch {
                // S-3: Whisper down.
                try? await vkSend(peerId, "⚠️ STT недоступен, audio сохранён, попробуй позже.")
                audit(decision: "error_whisper", outcome: "error",
                      msgId: msgId, peerId: peerId,
                      audioPath: audioPath?.path, durationS: audio.duration,
                      transcriptVk: audio.transcript,
                      totalMs: ms(since: started))
                return
            }
            sttMs = ms(since: sttStart)
            transcriptVk = audio.transcript        // record for later compare
            transcriptWhisper = transcriptText
            decisionTag = "used_whisper"
        }

        // Echo transcript обратно — Sergey видит "что услышал" сразу (V4-echo).
        let vkSendStart = clock()
        try? await vkSend(peerId, "👂 услышал: «\(transcriptText)»")
        let vkSendMs = ms(since: vkSendStart)

        // Inject в Happy с provenance prefix.
        let src = decisionTag == "used_vk" ? "vk-transcript" : "whisper"
        let prefixed = "[voice from Sergey, src=\(src), lang=ru]\n\(transcriptText)"

        let injectStart = clock()
        let reply: String
        do {
            reply = try await happyInject(prefixed, targetCwd)
        } catch {
            // S-4 (no running session) / S-5 (reply timeout) / др. инжект-ошибки.
            try? await vkSend(peerId, "⚠️ диспетчер не ответил: \(label(error))")
            audit(decision: "error_inject", outcome: "error",
                  msgId: msgId, peerId: peerId,
                  audioPath: audioPath?.path, durationS: audio.duration,
                  transcriptVk: transcriptVk, transcriptWhisper: transcriptWhisper,
                  sttMs: sttMs, vkSendMs: vkSendMs,
                  totalMs: ms(since: started))
            return
        }
        let injectMs = ms(since: injectStart)

        try? await vkSend(peerId, reply)

        audit(decision: decisionTag, outcome: "success",
              msgId: msgId, peerId: peerId,
              audioPath: audioPath?.path, durationS: audio.duration,
              transcriptVk: transcriptVk, transcriptWhisper: transcriptWhisper,
              sttMs: sttMs, injectMs: injectMs, vkSendMs: vkSendMs,
              totalMs: ms(since: started),
              happyReplyChars: reply.count)
    }

    // MARK: - helpers

    private func ms(since start: Date) -> Int {
        Int((clock().timeIntervalSince(start) * 1000).rounded())
    }

    private func label(_ error: any Error) -> String {
        // ponytail: дробная классификация Happy errors в Phase 2 audit, не сейчас.
        let s = "\(error)"
        if s.contains("noRunningSessionForCwd") { return "session offline" }
        if s.contains("waitTimeout") { return "timeout (>30s)" }
        return "error"
    }

    private func audit(
        decision: String, outcome: String, msgId: Int64, peerId: Int64,
        audioPath: String? = nil, durationS: Int? = nil,
        transcriptVk: String? = nil, transcriptWhisper: String? = nil,
        sttMs: Int? = nil, injectMs: Int? = nil, vkSendMs: Int? = nil,
        totalMs: Int, happyReplyChars: Int? = nil
    ) {
        let entry = AuditEntry(
            ts: AudioStorage.compactStamp(from: clock()),
            msgId: msgId, peerId: peerId,
            audioPath: audioPath, durationS: durationS,
            transcriptVk: transcriptVk, transcriptWhisper: transcriptWhisper,
            decision: decision, sttMs: sttMs, injectMs: injectMs, vkSendMs: vkSendMs,
            totalMs: totalMs, happyReplyChars: happyReplyChars, outcome: outcome
        )
        try? storage.appendAudit(entry)
    }
}
