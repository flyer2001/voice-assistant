import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import VoiceServiceCore

@Suite("POST /v1/alice — маршрут навыка")
struct AliceEndpointTests {

    /// Куда сложились принятые реплики — проверяем, что инжект вызвался.
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func makeApp(secret: String = "s3cret",
                         skillId: String? = "skill-1",
                         sink: Sink) -> some ApplicationProtocol {
        VoiceServiceApp.make(config: Configuration(
            token: "T",
            replyProvider: { _ in "unused" },
            alice: AliceConfig(pathSecret: secret, skillId: skillId,
                               inject: { text in sink.add(text) })
        ))
    }

    private func body(command: String, skillId: String = "skill-1", new: Bool = false) -> ByteBuffer {
        ByteBuffer(string: """
        {"session":{"new":\(new),"session_id":"s","skill_id":"\(skillId)","user_id":"u"},
         "request":{"command":"\(command)","original_utterance":"\(command)","type":"SimpleUtterance"},
         "version":"1.0"}
        """)
    }

    @Test("реплика принимается без Authorization — Яндекс его не шлёт")
    func acceptsWithoutBearer() async throws {
        let sink = Sink()
        try await makeApp(sink: sink).test(.router) { client in
            try await client.execute(
                uri: "/v1/alice/s3cret", method: .post, body: body(command: "проверь статус")
            ) { response in
                #expect(response.status == .ok)
                let text = String(buffer: response.body)
                #expect(text.contains("Передал"))
                #expect(text.contains("\"version\":\"1.0\""))
            }
        }
        // Инжект уходит фоновой задачей — даём ей отработать.
        try await Task.sleep(for: .milliseconds(200))
        #expect(sink.all == ["проверь статус"])
    }

    @Test("неверный секрет в пути — 404, инжекта нет")
    func rejectsWrongSecret() async throws {
        let sink = Sink()
        try await makeApp(sink: sink).test(.router) { client in
            try await client.execute(
                uri: "/v1/alice/guessed", method: .post, body: body(command: "вредная команда")
            ) { response in
                #expect(response.status == .notFound)
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(sink.all.isEmpty, "чужой запрос не должен попасть в сессию")
    }

    @Test("чужой skill_id отвергается, даже если секрет угадан")
    func rejectsWrongSkillId() async throws {
        let sink = Sink()
        try await makeApp(sink: sink).test(.router) { client in
            try await client.execute(
                uri: "/v1/alice/s3cret", method: .post,
                body: body(command: "вредная команда", skillId: "someone-else")
            ) { response in
                #expect(response.status == .forbidden)
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(sink.all.isEmpty)
    }

    @Test("битое тело — 400, а не падение")
    func rejectsMalformedBody() async throws {
        let sink = Sink()
        try await makeApp(sink: sink).test(.router) { client in
            try await client.execute(
                uri: "/v1/alice/s3cret", method: .post, body: ByteBuffer(string: "не json")
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
        #expect(sink.all.isEmpty)
    }

    @Test("приветствие при запуске не инжектится")
    func greetingNotInjected() async throws {
        let sink = Sink()
        try await makeApp(sink: sink).test(.router) { client in
            try await client.execute(
                uri: "/v1/alice/s3cret", method: .post,
                body: ByteBuffer(string: """
                {"session":{"new":true,"session_id":"s","skill_id":"skill-1","user_id":"u"},
                 "request":{"command":"","original_utterance":"","type":"SimpleUtterance"},
                 "version":"1.0"}
                """)
            ) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("Слушаю"))
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(sink.all.isEmpty)
    }

    @Test("остальные маршруты по-прежнему требуют токен")
    func otherRoutesStillProtected() async throws {
        let sink = Sink()
        try await makeApp(sink: sink).test(.router) { client in
            try await client.execute(
                uri: "/v1/voice/intent", method: .post,
                body: ByteBuffer(string: #"{"text":"x","client_id":"c","ts":"t"}"#)
            ) { response in
                #expect(response.status == .unauthorized,
                        "послабление для Алисы не должно открывать остальное")
            }
        }
    }

    @Test("без настройки навыка маршрут закрыт")
    func routeClosedWhenNotConfigured() async throws {
        let app = VoiceServiceApp.make(config: Configuration(
            token: "T", replyProvider: { _ in "unused" }
        ))
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/alice/s3cret", method: .post, body: body(command: "привет")
            ) { response in
                // 401, а не 404: послабление в авторизации включается только
                // вместе с настройкой навыка, поэтому запрос упирается в
                // проверку токена раньше, чем в отсутствие маршрута.
                #expect(response.status == .unauthorized)
                #expect(response.status != .ok, "главное — не обработать")
            }
        }
    }
}
