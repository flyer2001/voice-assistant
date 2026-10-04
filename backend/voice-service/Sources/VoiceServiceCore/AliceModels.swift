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

    public struct Meta: Decodable, Sendable {
        /// Чем говорят: приложение и устройство. Строка свободного вида,
        /// например «ru.yandex.searchplugin/7.16 (iPhone; iOS 18)».
        public let client_id: String?
    }

    public let session: Session
    public let request: Request?
    public let meta: Meta?
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
    /// Есть вопрос новее этого ответа — значит ответ ещё готовится.
    /// Без этого признака «повторяю ответ» звучало и когда ответ в работе, и
    /// когда нового не будет вовсе, а человек эти случаи не различал.
    public let isPending: Bool
    /// Сколько сообщений ещё лежит в очереди после этого. Нужно, чтобы
    /// человек знал, стоит ли говорить «дальше», а не угадывал.
    public let remaining: Int

    public init(text: String, isRepeat: Bool, isPending: Bool = false, remaining: Int = 0) {
        self.text = text
        self.isRepeat = isRepeat
        self.isPending = isPending
        self.remaining = remaining
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
    /// Просьба озвучить следующее сообщение, а не передать реплику дальше.
    case answerRequest
    /// Переслушать последнее, не листая очередь.
    case repeatRequest
    /// Выбросить очередь.
    case clearRequest
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
        let stripped = stripActivation(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        ).joined(separator: " ")

        // Команды проверяем до инжекта, но после приветствия: иначе реплика
        // человека уедет в управление очередью.
        if ["повтори", "повтори ответ", "повтори ещё раз", "ещё раз",
            "повтори пожалуйста"].contains(stripped) {
            return .repeatRequest
        }
        if ["очисти", "очисти очередь", "очистить очередь", "забудь",
            "забудь всё", "забудь все", "удали все сообщения",
            "удали всё", "удали все"].contains(stripped) {
            return .clearRequest
        }
        if isAnswerRequest(text) {
            return .answerRequest
        }
        // Реплика из одних служебных слов — человек запнулся, и пауза обрубила
        // фразу. Инжектить «алиса» как мысль нельзя.
        let meaningful = stripActivation(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        if meaningful.isEmpty {
            return .empty
        }
        return .accepted(text)
    }

    /// Слова, которыми начинается обращение к навыку. Алиса иногда отдаёт их
    /// внутри `command` («скажи личному ассистенту дай ответ», живые случаи
    /// 2026-10-02), и без их снятия просьба не узнаётся.
    static let activationWords: Set<String> = [
        "алиса", "попроси", "попросить", "спроси", "спросить", "скажи",
        "скажите", "передай", "передать", "у", "мой", "моего", "моему"
    ]

    /// Срезает служебное начало реплики. Падежи «личный/личного/личному» и
    /// «ассистент/ассистента/ассистенту» ловим по основе, а не списком.
    static func stripActivation(_ words: [String]) -> [String] {
        var rest = words
        while let first = rest.first,
              activationWords.contains(first)
                || first.hasPrefix("личн")
                || first.hasPrefix("ассистент") {
            rest.removeFirst()
        }
        return rest
    }

    /// Фразы, которыми человек просит озвучить готовый ответ.
    ///
    /// Нарочно узкий список: слово «ответ» само по себе встречается в обычных
    /// репликах («запиши мысль про ответы сервиса»), и такую диктовку нельзя
    /// принимать за просьбу прочитать ящик.
    static func isAnswerRequest(_ text: String) -> Bool {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let normalized = stripActivation(words).joined(separator: " ")
        if normalized == "ответ" { return true }
        // Листание очереди — та же команда, что запрос ответа: следующее
        // сообщение. Отдельной машинерии не нужно, разница в длине фразы.
        if ["дальше", "следующее", "следующий", "что ещё", "ещё"].contains(normalized) {
            return true
        }
        for form in ["дай ответ", "дать ответ", "дай ответа", "прочитай ответ",
                     "прочти ответ", "какой ответ", "твой ответ", "скажи ответ",
                     "озвучь ответ"] {
            if normalized.hasPrefix(form) { return true }
        }
        return false
    }

    /// Откуда реплика. Метатег `src` был жёсткой строкой «alice-station»,
    /// пока другой поверхности не было; теперь говорят и с телефона, и
    /// контекст у этих реплик разный.
    ///
    /// Неизвестный клиент не угадываем: подставить «station» по умолчанию
    /// значило бы молча выдавать новую поверхность за колонку.
    public static func surface(_ clientId: String?) -> String {
        let id = (clientId ?? "").lowercased()
        if id.isEmpty { return "alice-unknown" }
        if id.contains("quasar") || id.contains("station") || id.contains("aliced") {
            return "alice-station"
        }
        // Приложения на телефоне: поиск Яндекса и «Дом с Алисой»
        // (com.yandex.iot, снято живьём 04.10). Заодно ловим платформу,
        // когда она написана в строке прямым текстом.
        if id.contains("searchplugin") || id.contains("mobile.search")
            || id.contains("yandex.iot") || id.contains("iphone")
            || id.contains("android") {
            return "alice-phone"
        }
        if id.contains("browser") { return "alice-browser" }
        return "alice-unknown"
    }

    /// Ответ на «дай ответ»: либо текст из ящика, либо честное «пока нет».
    public static func answerReply(_ answer: AliceAnswer?) -> AliceResponse {
        let text = (answer?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = answer?.isPending ?? false

        if text.isEmpty {
            let spoken = pending
                ? "Ответ ещё готовится. Спроси через полминуты."
                : "Ответа пока нет."
            return AliceResponse(text: spoken, tts: spoken)
        }
        // Три разных случая, и человек обязан их различать на слух:
        // свежий ответ, прошлый ответ пока готовится новый, просто повтор.
        let spoken: String
        if pending {
            spoken = "Ответ ещё готовится. Пока прошлый: \(text)"
        } else if answer?.isRepeat == true {
            spoken = "Повторяю ответ: \(text)"
        } else {
            spoken = text
        }
        return AliceResponse(text: spoken + tail(answer?.remaining ?? 0),
                             tts: spoken + tail(answer?.remaining ?? 0))
    }

    /// Что сказать после очистки. Число называем: человек должен услышать,
    /// что именно выбросили, — команда необратимая.
    public static func clearReply(removed: Int) -> AliceResponse {
        let spoken: String
        switch removed {
        case 0: spoken = "Очередь и так пуста."
        case 1: spoken = "Очередь очищена, убрал одно сообщение."
        case 2: spoken = "Очередь очищена, убрал два сообщения."
        case 3: spoken = "Очередь очищена, убрал три сообщения."
        case 4: spoken = "Очередь очищена, убрал четыре сообщения."
        default: spoken = "Очередь очищена, убрал \(removed) сообщений."
        }
        return AliceResponse(text: spoken, tts: spoken)
    }

    /// Хвост про остаток очереди. Числительные словами: цифры Алиса читает
    /// сносно, но «ещё 2 сообщения» звучит канцелярски.
    static func tail(_ remaining: Int) -> String {
        switch remaining {
        case 0: return ""
        case 1: return " Есть ещё одно сообщение, скажи дальше."
        case 2: return " Есть ещё два сообщения, скажи дальше."
        case 3: return " Есть ещё три сообщения, скажи дальше."
        case 4: return " Есть ещё четыре сообщения, скажи дальше."
        default: return " Есть ещё \(remaining) сообщений, скажи дальше."
        }
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
        case .answerRequest, .repeatRequest:
            // Маршрут отвечает сам — через answerReply с содержимым ящика.
            // Сюда попадаем только если ящик прочитать не удалось.
            return answerReply(nil)
        case .clearRequest:
            return clearReply(removed: 0)
        }
    }
}
