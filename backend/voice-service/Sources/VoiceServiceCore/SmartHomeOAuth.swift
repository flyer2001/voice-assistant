import Foundation

/// Токен, выданный Яндексу для доступа к нашему навыку умного дома.
public struct OAuthToken: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
}

/// Минимальный OAuth 2.0 (authorization code) для связки аккаунта.
///
/// Платформа умного дома требует собственный сервис авторизации — своего
/// Яндекс не предоставляет. Пользователь один, поэтому ни регистрации, ни
/// нескольких клиентов тут нет: логин и пароль берутся из env.
///
/// Токен на диске: связка должна переживать перезапуск сервиса, иначе после
/// каждого деплоя Sergey'ю пришлось бы привязывать навык заново.
public final class OAuthStore: @unchecked Sendable {

    /// Год — верхняя граница жизни токена. Яндекс обновляет его по refresh,
    /// но если обновление сломается, молчаливая вечность хуже явной смерти.
    static let tokenLifetime: TimeInterval = 365 * 86400

    private struct Stored: Codable {
        var accessToken: String
        var refreshToken: String
        var issued: Date
    }

    private let lock = NSLock()
    private let path: URL
    private let login: String
    private let password: String
    private let clientId: String
    private let clientSecret: String

    /// Выданные, но ещё не обменянные коды. В памяти намеренно: код живёт
    /// секунды, и терять его при рестарте безопаснее, чем хранить.
    private var pendingCodes: Set<String> = []
    private var stored: Stored?

    public init(path: URL, login: String, password: String,
                clientId: String, clientSecret: String) {
        self.path = path
        self.login = login
        self.password = password
        self.clientId = clientId
        self.clientSecret = clientSecret
        if let data = try? Data(contentsOf: path) {
            self.stored = try? JSONDecoder().decode(Stored.self, from: data)
        }
    }

    /// Шаг 1: человек ввёл логин и пароль в нашей форме.
    public func issueCode(login: String, password: String) -> String? {
        guard login == self.login, password == self.password else { return nil }
        let code = Self.randomToken()
        lock.lock(); defer { lock.unlock() }
        pendingCodes.insert(code)
        return code
    }

    /// Шаг 2: Яндекс меняет код на токен. Код одноразовый — иначе
    /// перехваченный редирект можно переиграть.
    public func exchange(code: String, clientId: String, clientSecret: String) -> OAuthToken? {
        guard clientId == self.clientId, clientSecret == self.clientSecret else { return nil }
        lock.lock()
        guard pendingCodes.remove(code) != nil else { lock.unlock(); return nil }
        let token = Stored(accessToken: Self.randomToken(),
                           refreshToken: Self.randomToken(),
                           issued: Date())
        stored = token
        lock.unlock()
        persist(token)
        return OAuthToken(accessToken: token.accessToken,
                          refreshToken: token.refreshToken,
                          expiresIn: Int(Self.tokenLifetime))
    }

    /// Обновление по refresh-токену. Яндекс делает это сам, до истечения.
    public func refresh(refreshToken: String, clientId: String, clientSecret: String) -> OAuthToken? {
        guard clientId == self.clientId, clientSecret == self.clientSecret else { return nil }
        lock.lock()
        guard let current = stored, current.refreshToken == refreshToken else {
            lock.unlock(); return nil
        }
        let token = Stored(accessToken: Self.randomToken(),
                           refreshToken: Self.randomToken(),
                           issued: Date())
        stored = token
        lock.unlock()
        persist(token)
        return OAuthToken(accessToken: token.accessToken,
                          refreshToken: token.refreshToken,
                          expiresIn: Int(Self.tokenLifetime))
    }

    public func isValid(token: String, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let stored else { return false }
        guard stored.accessToken == token else { return false }
        return now.timeIntervalSince(stored.issued) < Self.tokenLifetime
    }

    /// Яндекс присылает отвязку, когда навык удалили. После неё ни токен не
    /// действителен, ни callback'и посылать нельзя.
    public func unlink() {
        lock.lock()
        stored = nil
        pendingCodes.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: path)
    }

    /// Текущий access-токен — им бэкенд подписывает callback в Яндекс.
    public var currentAccessToken: String? {
        lock.lock(); defer { lock.unlock() }
        return stored?.accessToken
    }

    private func persist(_ token: Stored) {
        if let data = try? JSONEncoder().encode(token) {
            try? data.write(to: path, options: .atomic)
        }
    }

    static func randomToken() -> String {
        // 32 байта энтропии, hex — попадает в URL и заголовки без escaping.
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
