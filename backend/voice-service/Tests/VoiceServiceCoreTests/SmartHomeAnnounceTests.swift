import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import VoiceServiceCore

@Suite("Постановка сообщения в очередь с сигналом на колонку")
struct SmartHomeAnnounceTests {

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func makeApp(calls: Calls) -> some ApplicationProtocol {
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
                announce: { text in calls.add(text) },
                basePath: "/alice-push"
            )
        ))
    }

    @Test("ручка сигнала закрыта токеном, несмотря на послабление для платформы")
    func announceRequiresOurToken() async throws {
        // Послабление в авторизации должно действовать только на ручки, куда
        // стучит Яндекс: /auth, /token и /v1.0. Всё остальное под префиксом
        // навыка обязано остаться за нашим токеном — иначе любой желающий
        // дёргает колонку.
        let calls = Calls()
        try await makeApp(calls: calls).test(.router) { client in
            try await client.execute(
                uri: "/alice-push/announce", method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: #"{"text":"посторонний","source":"злоумышленник"}"#)
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
        #expect(calls.all.isEmpty, "без токена сообщение не ставится и колонка молчит")
    }

    @Test("с нашим токеном сообщение ставится в очередь")
    func announceWithToken() async throws {
        let calls = Calls()
        try await makeApp(calls: calls).test(.router) { client in
            try await client.execute(
                uri: "/alice-push/announce", method: .post,
                headers: [.authorization: "Bearer T", .contentType: "application/json"],
                body: ByteBuffer(string: #"{"text":"слой ждёт коммита","source":"авито"}"#)
            ) { response in
                #expect(response.status == .ok)
            }
        }
        #expect(calls.all == ["слой ждёт коммита"])
    }

    @Test("пустой текст не ставится — звонить без сообщения незачем")
    func emptyTextRejected() async throws {
        let calls = Calls()
        try await makeApp(calls: calls).test(.router) { client in
            try await client.execute(
                uri: "/alice-push/announce", method: .post,
                headers: [.authorization: "Bearer T", .contentType: "application/json"],
                body: ByteBuffer(string: #"{"text":"   ","source":"авито"}"#)
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
        #expect(calls.all.isEmpty)
    }
}
