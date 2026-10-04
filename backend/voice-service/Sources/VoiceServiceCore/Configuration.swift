import Foundation

/// Backend configuration. `token` is the static Bearer accepted on the
/// Authorization header. `replyProvider` produces the assistant reply for
/// a given intent request — in tests it's a stub closure, in production
/// it will forward to Happy inject (port of inject.mjs, see Tasks B4-B5).
public struct Configuration: Sendable {
    public let token: String
    public let replyProvider: @Sendable (IntentRequest) async throws -> String
    public let sttProvider: STTProvider?
    public let vkSendProvider: (@Sendable (_ peerId: Int64, _ text: String) async throws -> Void)?
    public let requestLogger: RequestLogger?
    public let audioLimits: AudioLimits
    /// Навык Алисы. Nil — маршрут не поднимается вовсе.
    public let alice: AliceConfig?
    /// Навык умного дома: виртуальная лампочка для пуша на колонку.
    /// Nil — ни ручки OAuth, ни Provider API не поднимаются.
    public let smartHome: SmartHomeConfig?

    public init(
        token: String,
        replyProvider: @escaping @Sendable (IntentRequest) async throws -> String,
        sttProvider: STTProvider? = nil,
        vkSendProvider: (@Sendable (_ peerId: Int64, _ text: String) async throws -> Void)? = nil,
        requestLogger: RequestLogger? = nil,
        audioLimits: AudioLimits = .default,
        alice: AliceConfig? = nil,
        smartHome: SmartHomeConfig? = nil
    ) {
        self.token = token
        self.replyProvider = replyProvider
        self.sttProvider = sttProvider
        self.vkSendProvider = vkSendProvider
        self.requestLogger = requestLogger
        self.audioLimits = audioLimits
        self.alice = alice
        self.smartHome = smartHome
    }
}

/// Настройки навыка умного дома.
///
/// Лампочка «Уведомление» ничего не освещает: это переключатель, за который
/// дёргает бэкенд, чтобы сценарий в «Доме с Алисой» проиграл звук на
/// колонке. План — docs/plans/2026-10-04-alice-smart-home-push.md
public struct SmartHomeConfig: Sendable {
    public let store: OAuthStore
    public let state: SmartHomeState
    public let deviceId: String
    public let deviceName: String
    /// Поставить сообщение в голосовую очередь и мигнуть лампочкой.
    /// Вызывается агентами через закрытую нашим токеном ручку.
    public let announce: @Sendable (String) async -> Void

    public init(store: OAuthStore, state: SmartHomeState,
                deviceId: String, deviceName: String,
                announce: @escaping @Sendable (String) async -> Void = { _ in }) {
        self.store = store
        self.state = state
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.announce = announce
    }
}

/// Настройки маршрута навыка Алисы.
///
/// Bearer-токеном не закрыть: Яндекс шлёт запросы сам и заголовок не
/// добавляет. Поэтому секрет живёт в самом пути (`/v1/alice/<secret>`), а
/// вдобавок сверяется идентификатор навыка из тела запроса. По HTTPS путь
/// наружу не виден.
public struct AliceConfig: Sendable {
    public let pathSecret: String
    /// Ожидаемый skill_id. Пусто — не проверяем (удобно в тестах).
    public let skillId: String?
    /// Куда девать распознанную реплику. Вызывается в фоне: ответ Диалогам
    /// уходит сразу, иначе не уложиться в 4.5 секунды.
    public let inject: @Sendable (String) async -> Void
    /// Забирает подготовленный ответ, если он есть, и помечает его прочитанным.
    /// Так колонка озвучивает ответ, хотя навык не может заговорить первым:
    /// человек спрашивает «дай ответ», когда текст уже лежит.
    public let takeAnswer: @Sendable () async -> AliceAnswer?
    /// Переслушать последнее, не листая очередь.
    public let repeatLast: @Sendable () async -> AliceAnswer?
    /// Выбросить очередь, вернув число убранных сообщений.
    public let clearQueue: @Sendable () async -> Int

    public init(pathSecret: String,
                skillId: String? = nil,
                inject: @escaping @Sendable (String) async -> Void,
                takeAnswer: @escaping @Sendable () async -> AliceAnswer? = { nil },
                repeatLast: @escaping @Sendable () async -> AliceAnswer? = { nil },
                clearQueue: @escaping @Sendable () async -> Int = { 0 }) {
        self.pathSecret = pathSecret
        self.skillId = skillId
        self.inject = inject
        self.takeAnswer = takeAnswer
        self.repeatLast = repeatLast
        self.clearQueue = clearQueue
    }
}

/// Server-side audio constraints for POST /v1/voice/audio. Production
/// defaults rejct silent/empty uploads and impose a 32 MB body cap (≈5 min
/// at 16 kHz mono Int16). `lenient` is a test helper that disables all
/// checks so unit tests can use synthetic 16-byte payloads.
public struct AudioLimits: Sendable {
    public let minAudioBytes: Int
    public let maxAudioBytes: Int
    public let maxDeclaredDurationS: Double

    public init(minAudioBytes: Int, maxAudioBytes: Int, maxDeclaredDurationS: Double) {
        self.minAudioBytes = minAudioBytes
        self.maxAudioBytes = maxAudioBytes
        self.maxDeclaredDurationS = maxDeclaredDurationS
    }

    public static let `default` = AudioLimits(
        minAudioBytes: 1024,
        maxAudioBytes: 32 * 1024 * 1024,
        maxDeclaredDurationS: 60
    )

    public static let lenient = AudioLimits(
        minAudioBytes: 0,
        maxAudioBytes: .max,
        maxDeclaredDurationS: .infinity
    )
}
