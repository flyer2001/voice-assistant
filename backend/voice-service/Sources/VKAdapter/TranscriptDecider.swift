import Foundation

/// Решает: используем готовую VK transcript или гоним audio в Whisper.
/// Чистая функция, без I/O. См. specs/vk-bot-mvp.md S-1 vs S-2.
public enum TranscriptDecider {
    public enum Decision: Equatable, Sendable {
        case useVK(String)
        case useWhisper
    }

    /// transcript_state == "done" + non-empty transcript → VK wins.
    /// Иначе всегда Whisper (async VK event ловить не будем в MVP).
    public static func decide(transcript: String?, transcriptState: String?) -> Decision {
        if transcriptState == "done", let t = transcript, !t.isEmpty {
            return .useVK(t)
        }
        return .useWhisper
    }
}
