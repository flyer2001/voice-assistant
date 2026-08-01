import Foundation

/// Решает: используем готовую VK transcript или гоним audio в Whisper.
/// Чистая функция, без I/O. См. specs/vk-bot-mvp.md S-1 vs S-2.
///
/// ⚠️ На практике ветка `.useVK` никогда не срабатывает. Проверено
/// 2026-08-01 через `messages.getById` на шести сообщениях (msg_id 253,
/// 257, 262, 335, 343, 350; самое старое — от 22 июня, времени на
/// транскрибацию было более чем достаточно): в объекте `audio_message`
/// поля `transcript` **нет вообще**, `transcript_state` = nil. Не пустая
/// строка и не "error" — ключи отсутствуют. Похоже, VK не отдаёт свою
/// STT-расшифровку по group access_token.
///
/// Следствия: `transcript_vk` в audit.jsonl всегда null (0 из 26 записей),
/// а сравнение «Whisper vs VK» как проверка качества недостижимо — секция
/// выброшена из docs/voice-patterns.md.
///
/// Код оставлен намеренно: он копеечный и сработает сам, если VK когда-то
/// начнёт отдавать поле. Проверять повторно — только если появится повод.
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
