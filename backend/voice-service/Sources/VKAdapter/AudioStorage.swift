import Foundation

/// Хранит raw .ogg + append-only JSONL audit. Plain filesystem, без БД.
/// Path layout per specs/vk-bot-mvp.md SP3.
public struct AudioStorage: Sendable {
    public let rawDir: URL
    public let auditPath: URL

    public init(rawDir: URL, auditPath: URL) {
        self.rawDir = rawDir
        self.auditPath = auditPath
    }

    /// Save audio bytes → returns absolute path on disk.
    public func saveAudio(_ bytes: Data, msgId: Int64, ts: Date = .now) throws -> URL {
        try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
        let stamp = Self.compactStamp(from: ts)
        let url = rawDir.appendingPathComponent("\(stamp)-msg\(msgId).ogg")
        try bytes.write(to: url)
        return url
    }

    /// Filename-safe ISO8601: `:` → `-`, millisecond precision.
    public static func compactStamp(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    /// Append one JSONL line. Best-effort, errors swallowed (logs separately).
    public func appendAudit(_ entry: AuditEntry) throws {
        let data = try JSONEncoder.audit.encode(entry)
        try FileManager.default.createDirectory(
            at: auditPath.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: auditPath.path) {
            FileManager.default.createFile(atPath: auditPath.path, contents: nil)
        }
        let fh = try FileHandle(forWritingTo: auditPath)
        defer { try? fh.close() }
        try fh.seekToEnd()
        try fh.write(contentsOf: data)
        try fh.write(contentsOf: Data("\n".utf8))
    }
}

public struct AuditEntry: Codable, Sendable, Equatable {
    public let ts: String
    public let msgId: Int64
    public let peerId: Int64
    public let audioPath: String?
    public let durationS: Int?
    public let transcriptVk: String?
    public let transcriptWhisper: String?
    public let decision: String       // "used_vk" | "used_whisper" | "drop_*" | "error_*"
    public let sttMs: Int?
    public let injectMs: Int?
    public let vkSendMs: Int?
    public let totalMs: Int
    public let happyReplyChars: Int?
    public let outcome: String        // "success" | "error" | "dropped"

    public init(
        ts: String, msgId: Int64, peerId: Int64,
        audioPath: String? = nil, durationS: Int? = nil,
        transcriptVk: String? = nil, transcriptWhisper: String? = nil,
        decision: String, sttMs: Int? = nil, injectMs: Int? = nil,
        vkSendMs: Int? = nil, totalMs: Int,
        happyReplyChars: Int? = nil, outcome: String
    ) {
        self.ts = ts; self.msgId = msgId; self.peerId = peerId
        self.audioPath = audioPath; self.durationS = durationS
        self.transcriptVk = transcriptVk; self.transcriptWhisper = transcriptWhisper
        self.decision = decision; self.sttMs = sttMs; self.injectMs = injectMs
        self.vkSendMs = vkSendMs; self.totalMs = totalMs
        self.happyReplyChars = happyReplyChars; self.outcome = outcome
    }

    enum CodingKeys: String, CodingKey {
        case ts, msgId = "msg_id", peerId = "peer_id"
        case audioPath = "audio_path", durationS = "duration_s"
        case transcriptVk = "transcript_vk", transcriptWhisper = "transcript_whisper"
        case decision, sttMs = "stt_ms", injectMs = "inject_ms"
        case vkSendMs = "vk_send_ms", totalMs = "total_ms"
        case happyReplyChars = "happy_reply_chars", outcome
    }
}

private extension JSONEncoder {
    static let audit: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()
}
