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

    public init(
        token: String,
        replyProvider: @escaping @Sendable (IntentRequest) async throws -> String,
        sttProvider: STTProvider? = nil,
        vkSendProvider: (@Sendable (_ peerId: Int64, _ text: String) async throws -> Void)? = nil,
        requestLogger: RequestLogger? = nil,
        audioLimits: AudioLimits = .default,
        alice: AliceConfig? = nil
    ) {
        self.token = token
        self.replyProvider = replyProvider
        self.sttProvider = sttProvider
        self.vkSendProvider = vkSendProvider
        self.requestLogger = requestLogger
        self.audioLimits = audioLimits
        self.alice = alice
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

    public init(pathSecret: String,
                skillId: String? = nil,
                inject: @escaping @Sendable (String) async -> Void) {
        self.pathSecret = pathSecret
        self.skillId = skillId
        self.inject = inject
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
