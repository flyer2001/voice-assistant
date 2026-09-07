import Foundation

/// Протокол Яндекс Диалогов — только те поля, что нам нужны.
///
/// Полный формат: https://yandex.ru/dev/dialogs/alice/doc/ru/request
/// Намеренно не тащим всё: платформа добавляет поля, а нам от запроса нужны
/// текст реплики, признак новой сессии и идентификатор навыка для проверки.
public struct AliceRequest: Decodable, Sendable {
    public struct Session: Decodable, Sendable {
        public let new: Bool
        public let session_id: String?
        public let skill_id: String?
        public let user_id: String?
    }

    public struct Request: Decodable, Sendable {
        /// Реплика без служебных слов активации. Пусто, когда пользователь
        /// только запустил навык и ещё ничего не сказал.
        public let command: String?
        /// Реплика как есть, включая «алиса, запусти…».
        public let original_utterance: String?
        public let type: String?
    }

    public let session: Session
    public let request: Request?
    public let version: String?
}

/// Ответ Диалогам. Отвечаем всегда быстро — работу делаем в фоне, иначе
/// упрёмся в таймаут 4.5 секунды.
public struct AliceResponse: Encodable, Sendable {
    public struct Payload: Encodable, Sendable {
        public let text: String
        /// Что произнести вслух. Отличается от текста, когда написанное
        /// плохо читается голосом.
        public let tts: String?
        public let end_session: Bool
    }

    public let response: Payload
    public let version: String

    public init(text: String, tts: String? = nil, endSession: Bool = false) {
        // 1024 символа — предел, после которого реплику обрывает.
        // Нам столько не нужно, но пусть режется предсказуемо.
        let capped = String(text.prefix(1024))
        self.response = Payload(text: capped,
                                tts: tts.map { String($0.prefix(1024)) },
                                end_session: endSession)
        self.version = "1.0"
    }
}

/// Что ответить на реплику.
public enum AliceOutcome: Equatable, Sendable {
    /// Приветствие при запуске навыка — команды ещё не было.
    case greeting
    /// Реплика принята и ушла в сессию.
    case accepted(String)
    /// Пустая реплика внутри сессии — человек промолчал или его не расслышали.
    case empty
}

public enum AliceHandler {
    /// Разбирает запрос и решает, что с ним делать. Чистая функция —
    /// инжект и сеть снаружи.
    public static func decide(_ req: AliceRequest) -> AliceOutcome {
        let text = (req.request?.command ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if req.session.new && text.isEmpty {
            return .greeting
        }
        if text.isEmpty {
            return .empty
        }
        return .accepted(text)
    }

    /// Текст ответа на каждый исход. Голосом отвечаем короче, чем пишем.
    public static func reply(for outcome: AliceOutcome) -> AliceResponse {
        switch outcome {
        case .greeting:
            return AliceResponse(
                text: "Слушаю. Скажите, что передать.",
                tts: "Слушаю. Скажите, что передать."
            )
        case .accepted:
            // Не пересказываем услышанное: на длинной реплике это съест
            // секунды озвучки, а человек и так знает, что сказал.
            return AliceResponse(text: "Передал.", tts: "Передал.")
        case .empty:
            return AliceResponse(
                text: "Не расслышала. Повторите, пожалуйста.",
                tts: "Не расслышала. Повторите, пожалуйста."
            )
        }
    }
}
