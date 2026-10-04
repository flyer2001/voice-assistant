import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import VoiceServiceCore

@Suite("Ручки OAuth навыка умного дома")
struct SmartHomeOAuthEndpointTests {

    private func makeApp() -> some ApplicationProtocol {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sh-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return VoiceServiceApp.make(config: Configuration(
            token: "T",
            replyProvider: { _ in "unused" },
            smartHome: SmartHomeConfig(
                store: OAuthStore(path: dir.appendingPathComponent("oauth.json"),
                                  login: "sergey", password: "s3cret",
                                  clientId: "yandex", clientSecret: "client-s3cret"),
                state: SmartHomeState(path: dir.appendingPathComponent("state.json")),
                deviceId: "notify-1",
                deviceName: "Уведомление",
                basePath: "/alice-push"
            )
        ))
    }

    /// Форма логина отдаётся браузеру Sergey'я при связке аккаунта.
    @Test("GET /auth отдаёт форму с сохранением state и redirect_uri")
    func authFormRendered() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/alice-push/auth?state=abc&client_id=yandex&redirect_uri=https%3A%2F%2Fsocial.yandex.net%2Fbroker%2Fredirect&response_type=code",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let html = String(buffer: response.body)
                #expect(html.contains("<form"))
                #expect(html.contains("abc"), "state должен вернуться обратно")
                #expect(html.contains("social.yandex.net"), "redirect_uri сохраняется")
            }
        }
    }

    @Test("верный логин редиректит на redirect_uri с кодом и state")
    func validLoginRedirects() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/alice-push/auth", method: .post,
                headers: [.contentType: "application/x-www-form-urlencoded"],
                body: ByteBuffer(string: "login=sergey&password=s3cret&state=abc&redirect_uri=https://social.yandex.net/broker/redirect")
            ) { response in
                #expect(response.status == .found)
                let location = response.headers[.location] ?? ""
                #expect(location.hasPrefix("https://social.yandex.net/broker/redirect?"))
                #expect(location.contains("code="))
                #expect(location.contains("state=abc"))
            }
        }
    }

    @Test("неверный пароль — 401 и никакого кода")
    func wrongPasswordRejected() async throws {
        try await makeApp().test(.router) { client in
            try await client.execute(
                uri: "/alice-push/auth", method: .post,
                headers: [.contentType: "application/x-www-form-urlencoded"],
                body: ByteBuffer(string: "login=sergey&password=подобранный&state=abc&redirect_uri=https://social.yandex.net/broker/redirect")
            ) { response in
                #expect(response.status == .unauthorized)
                #expect(!String(buffer: response.body).contains("code="))
                #expect(response.headers[.location] == nil, "редиректа быть не должно")
            }
        }
    }

    @Test("код меняется на токен, повторно — нет")
    func tokenExchange() async throws {
        try await makeApp().test(.router) { client in
            var code = ""
            try await client.execute(
                uri: "/alice-push/auth", method: .post,
                headers: [.contentType: "application/x-www-form-urlencoded"],
                body: ByteBuffer(string: "login=sergey&password=s3cret&state=abc&redirect_uri=https://social.yandex.net/broker/redirect")
            ) { response in
                let location = response.headers[.location] ?? ""
                code = location.components(separatedBy: "code=").last?
                    .components(separatedBy: "&").first ?? ""
                #expect(!code.isEmpty)
            }

            let form = "grant_type=authorization_code&code=\(code)&client_id=yandex&client_secret=client-s3cret"
            try await client.execute(
                uri: "/alice-push/token", method: .post,
                headers: [.contentType: "application/x-www-form-urlencoded"],
                body: ByteBuffer(string: form)
            ) { response in
                #expect(response.status == .ok)
                let json = String(buffer: response.body)
                #expect(json.contains("access_token"))
                #expect(json.contains("refresh_token"))
                #expect(json.contains("expires_in"))
            }

            // Перехваченный редирект не должен переигрываться.
            try await client.execute(
                uri: "/alice-push/token", method: .post,
                headers: [.contentType: "application/x-www-form-urlencoded"],
                body: ByteBuffer(string: form)
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("чужой client_secret токен не получает")
    func wrongClientSecret() async throws {
        try await makeApp().test(.router) { client in
            var code = ""
            try await client.execute(
                uri: "/alice-push/auth", method: .post,
                headers: [.contentType: "application/x-www-form-urlencoded"],
                body: ByteBuffer(string: "login=sergey&password=s3cret&state=abc&redirect_uri=https://social.yandex.net/broker/redirect")
            ) { response in
                code = (response.headers[.location] ?? "")
                    .components(separatedBy: "code=").last?
                    .components(separatedBy: "&").first ?? ""
            }
            try await client.execute(
                uri: "/alice-push/token", method: .post,
                headers: [.contentType: "application/x-www-form-urlencoded"],
                body: ByteBuffer(string: "grant_type=authorization_code&code=\(code)&client_id=yandex&client_secret=подобранный")
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("без настройки навыка ручки OAuth закрыты")
    func routesClosedWhenNotConfigured() async throws {
        let app = VoiceServiceApp.make(config: Configuration(
            token: "T", replyProvider: { _ in "unused" }
        ))
        try await app.test(.router) { client in
            try await client.execute(uri: "/alice-push/auth", method: .get) { response in
                #expect(response.status != .ok, "главное — не обработать")
            }
        }
    }
}
