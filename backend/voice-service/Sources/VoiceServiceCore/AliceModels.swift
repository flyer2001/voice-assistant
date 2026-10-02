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

/// Готовый ответ из ящика. `isRepeat` — его уже озвучивали: ящик нарочно не
/// одноразовый (человек мог не расслышать), но повтор нельзя подавать как
/// свежий ответ.
public struct AliceAnswer: Sendable, Equatable {
    public let text: String
    public let isRepeat: Bool

    public init(text: String, isRepeat: Bool) {
        self.text = text
        self.isRepeat = isRepeat
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
    /// Просьба озвучить подготовленный ответ, а не передать реплику дальше.
    case answerRequest
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
        if isAnswerRequest(text) {
            return .answerRequest
        }
        return .accepted(text)
    }

    /// Фразы, которыми человек просит озвучить готовый ответ.
    ///
    /// Нарочно узкий список: слово «ответ» само по себе встречается в обычных
    /// репликах («запиши мысль про ответы сервиса»), и такую диктовку нельзя
    /// принимать за просьбу прочитать ящик.
    static func isAnswerRequest(_ text: String) -> Bool {
        var words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        // Алиса иногда отдаёт реплику вместе с активационным именем
        // («попроси личного ассистента дать ответ», живой случай 2026-10-02).
        // Срезаем служебное начало, иначе просьба не узнаётся.
        let activation: Set<String> = ["алиса", "попроси", "попросить", "спроси",
                                       "спросить", "у", "личного", "личный",
                                       "ассистента", "ассистент", "мой", "моего"]
        while let first = words.first, activation.contains(first) {
            words.removeFirst()
        }
        let normalized = words.joined(separator: " ")
        if normalized == "ответ" { return true }
        for form in ["дай ответ", "дать ответ", "дай ответа", "прочитай ответ",
                     "прочти ответ", "какой ответ", "твой ответ", "скажи ответ",
                     "озвучь ответ"] {
            if normalized.hasPrefix(form) { return true }
        }
        return false
    }

    /// Ответ на «дай ответ»: либо текст из ящика, либо честное «пока нет».
    public static func answerReply(_ answer: AliceAnswer?) -> AliceResponse {
        guard let answer,
              case let text = answer.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return AliceResponse(text: "Ответа пока нет.", tts: "Ответа пока нет.")
        }
        // Повтор обязан звучать как повтор: иначе ответ на прошлый вопрос
        // сойдёт за ответ на новый, и человек этого не различит.
        let spoken = answer.isRepeat ? "Повторяю ответ: \(text)" : text
        return AliceResponse(text: spoken, tts: spoken)
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
        case .answerRequest:
            // Маршрут отвечает сам — через answerReply с содержимым ящика.
            // Сюда попадаем только если ящик прочитать не удалось.
            return answerReply(nil)
        }
    }
}
