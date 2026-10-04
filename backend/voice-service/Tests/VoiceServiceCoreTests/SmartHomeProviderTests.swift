import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import VoiceServiceCore

@Suite("Provider API навыка умного дома — /v1.0")
struct SmartHomeProviderTests {

    /// Приложение плюс уже связанный аккаунт: токен выдан, как после
    /// привязки навыка в «Доме с Алисой».
    private func makeLinked() -> (app: any ApplicationProtocol,
                                  token: String,
                                  state: SmartHomeState,
                                  store: OAuthStore) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sh-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = OAuthStore(path: dir.appendingPathComponent("oauth.json"),
                               login: "sergey", password: "s3cret",
                               clientId: "yandex", clientSecret: "client-s3cret")
        let state = SmartHomeState(path: dir.appendingPathComponent("state.json"))
        let code = store.issueCode(login: "sergey", password: "s3cret")!
        let token = store.exchange(code: code, clientId: "yandex",
                                   clientSecret: "client-s3cret")!
        let app = VoiceServiceApp.make(config: Configuration(
            token: "T",
            replyProvider: { _ in "unused" },
            smartHome: SmartHomeConfig(store: store, state: state,
                                       deviceId: "notify-1", deviceName: "Уведомление")
        ))
        return (app, token.accessToken, state, store)
    }

    private func auth(_ token: String) -> HTTPFields {
        [.authorization: "Bearer \(token)", .contentType: "application/json"]
    }

    /// Приложение с собственным префиксом — так навык не занимает корень
    /// чужого сайта.
    private func makePrefixed(_ prefix: String) -> any ApplicationProtocol {
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
                deviceId: "notify-1", deviceName: "Уведомление",
                basePath: prefix
            )
        ))
    }

    @Test("ручки живут под своим префиксом, а не в корне сайта")
    func routesHonourBasePath() async throws {
        // Домен делится с другим сервисом: занимать его /v1.0 нельзя.
        try await makePrefixed("/alice-push").test(.router) { client in
            try await client.execute(uri: "/alice-push/v1.0", method: .head) { response in
                #expect(response.status == .ok)
            }
            // Со слешем на конце — платформа стучит именно так.
            try await client.execute(uri: "/alice-push/v1.0/", method: .head) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(uri: "/alice-push/v1.0/user/devices",
                                     method: .get) { response in
                #expect(response.status == .unauthorized, "ручка есть, но закрыта")
            }
            try await client.execute(uri: "/alice-push/auth", method: .get) { response in
                #expect(response.status == .ok, "форма авторизации тоже под префиксом")
            }
            // Корень сайта при этом свободен: обработчика там нет. Ответ
            // 401, а не 404 — проверка токена стоит перед маршрутизацией и
            // отбивает неизвестный путь раньше. Важно, что не обработали.
            try await client.execute(uri: "/v1.0", method: .head) { response in
                #expect(response.status != .ok, "корень чужого домена не занимаем")
            }
        }
    }

    @Test("HEAD /v1.0 — проверка доступности, без авторизации")
    func pingIsOpen() async throws {
        let env = makeLinked()
        try await env.app.test(.router) { client in
            try await client.execute(uri: "/v1.0", method: .head) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("список устройств отдаёт нашу лампочку")
    func devicesListed() async throws {
        let env = makeLinked()
        try await env.app.test(.router) { client in
            try await client.execute(uri: "/v1.0/user/devices", method: .get,
                                     headers: auth(env.token)) { response in
                #expect(response.status == .ok)
                let json = String(buffer: response.body)
                #expect(json.contains("notify-1"))
                #expect(json.contains("Уведомление"))
                #expect(json.contains("devices.types.light"))
                #expect(json.contains("devices.capabilities.on_off"))
                #expect(json.contains("request_id"))
            }
        }
    }

    @Test("без токена и с чужим токеном — 401, устройств не видно")
    func devicesRequireToken() async throws {
        let env = makeLinked()
        try await env.app.test(.router) { client in
            try await client.execute(uri: "/v1.0/user/devices", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
            try await client.execute(uri: "/v1.0/user/devices", method: .get,
                                     headers: auth("подобранный")) { response in
                #expect(response.status == .unauthorized)
                #expect(!String(buffer: response.body).contains("notify-1"))
            }
        }
    }

    @Test("опрос отдаёт сохранённое состояние, а не вычисленное")
    func queryReportsStoredState() async throws {
        // Review Focus №1: Яндекс опрашивает в любой момент, в том числе
        // через миллисекунды после гашения. Соврать тут — значит сорвать
        // сценарий.
        let env = makeLinked()
        env.state.set(on: true)
        try await env.app.test(.router) { client in
            try await client.execute(
                uri: "/v1.0/user/devices/query", method: .post, headers: auth(env.token),
                body: ByteBuffer(string: #"{"devices":[{"id":"notify-1"}]}"#)
            ) { response in
                #expect(response.status == .ok)
                let json = String(buffer: response.body)
                #expect(json.contains("\"value\":true"))
                #expect(json.contains("\"instance\":\"on\""))
            }
            env.state.set(on: false)
            try await client.execute(
                uri: "/v1.0/user/devices/query", method: .post, headers: auth(env.token),
                body: ByteBuffer(string: #"{"devices":[{"id":"notify-1"}]}"#)
            ) { response in
                #expect(String(buffer: response.body).contains("\"value\":false"))
            }
        }
    }

    @Test("действие переключает лампочку и отвечает DONE")
    func actionTogglesDevice() async throws {
        let env = makeLinked()
        try await env.app.test(.router) { client in
            try await client.execute(
                uri: "/v1.0/user/devices/action", method: .post, headers: auth(env.token),
                body: ByteBuffer(string: """
                {"payload":{"devices":[{"id":"notify-1","capabilities":[
                 {"type":"devices.capabilities.on_off",
                  "state":{"instance":"on","value":true}}]}]}}
                """)
            ) { response in
                #expect(response.status == .ok)
                let json = String(buffer: response.body)
                #expect(json.contains("DONE"))
                #expect(json.contains("notify-1"))
            }
            #expect(env.state.isOn == true, "состояние должно измениться")
        }
    }

    @Test("действие на чужое устройство — не DONE, состояние не меняется")
    func actionOnUnknownDevice() async throws {
        let env = makeLinked()
        try await env.app.test(.router) { client in
            try await client.execute(
                uri: "/v1.0/user/devices/action", method: .post, headers: auth(env.token),
                body: ByteBuffer(string: """
                {"payload":{"devices":[{"id":"чужая-лампа","capabilities":[
                 {"type":"devices.capabilities.on_off",
                  "state":{"instance":"on","value":true}}]}]}}
                """)
            ) { response in
                #expect(String(buffer: response.body).contains("ERROR"))
            }
            #expect(env.state.isOn == false)
        }
    }

    @Test("отвязка убивает связку — дальше 401")
    func unlinkKillsLink() async throws {
        // Review Focus №4: после отвязки Яндекс считает ошибкой и наши
        // callback'и, и действующий токен.
        let env = makeLinked()
        try await env.app.test(.router) { client in
            try await client.execute(uri: "/v1.0/user/unlink", method: .post,
                                     headers: auth(env.token)) { response in
                #expect(response.status == .ok)
            }
            try await client.execute(uri: "/v1.0/user/devices", method: .get,
                                     headers: auth(env.token)) { response in
                #expect(response.status == .unauthorized)
            }
        }
        #expect(env.store.currentAccessToken == nil)
    }

    @Test("request_id возвращается из заголовка запроса")
    func echoesRequestId() async throws {
        // Яндекс сопоставляет ответ с запросом по этому полю; выдумывать
        // своё нельзя.
        let env = makeLinked()
        try await env.app.test(.router) { client in
            var headers = auth(env.token)
            headers[.init("X-Request-Id")!] = "req-42"
            try await client.execute(uri: "/v1.0/user/devices", method: .get,
                                     headers: headers) { response in
                #expect(String(buffer: response.body).contains("req-42"))
            }
        }
    }
}
