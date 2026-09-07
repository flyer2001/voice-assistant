import Foundation
import Testing
@testable import VoiceServiceCore

@Suite("Навык Алисы — разбор реплики")
struct AliceHandlerTests {

    private func req(command: String?, new: Bool = false, skillId: String? = "skill-1") -> AliceRequest {
        let json = """
        {
          "session": { "new": \(new), "session_id": "s1",
                       "skill_id": \(skillId.map { "\"\($0)\"" } ?? "null"),
                       "user_id": "u1" },
          "request": { "command": \(command.map { "\"\($0)\"" } ?? "null"),
                       "original_utterance": \(command.map { "\"\($0)\"" } ?? "null"),
                       "type": "SimpleUtterance" },
          "version": "1.0"
        }
        """
        return try! JSONDecoder().decode(AliceRequest.self, from: Data(json.utf8))
    }

    @Test("запуск навыка без команды — приветствие, ничего не инжектим")
    func greetingOnNewSession() {
        #expect(AliceHandler.decide(req(command: nil, new: true)) == .greeting)
        #expect(AliceHandler.decide(req(command: "", new: true)) == .greeting)
    }

    @Test("реплика принимается и отдаётся наружу")
    func acceptsCommand() {
        let outcome = AliceHandler.decide(req(command: "запиши мысль про кэширование"))
        #expect(outcome == .accepted("запиши мысль про кэширование"))
    }

    @Test("пробелы по краям срезаются")
    func trimsWhitespace() {
        #expect(AliceHandler.decide(req(command: "  проверь статус  "))
                == .accepted("проверь статус"))
    }

    @Test("молчание внутри сессии — просим повторить, а не инжектим пустоту")
    func emptyInsideSession() {
        #expect(AliceHandler.decide(req(command: "", new: false)) == .empty)
        #expect(AliceHandler.decide(req(command: "   ", new: false)) == .empty)
        #expect(AliceHandler.decide(req(command: nil, new: false)) == .empty)
    }

    @Test("команда в первой же реплике не теряется")
    func commandOnNewSession() {
        // Алиса умеет запускать навык и сразу передавать текст: «алиса,
        // запусти диспетчер и запиши мысль». Терять такую реплику нельзя.
        let outcome = AliceHandler.decide(req(command: "запиши мысль", new: true))
        #expect(outcome == .accepted("запиши мысль"))
    }

    @Test("ответ на принятую реплику короткий и не пересказывает сказанное")
    func replyIsShort() {
        let r = AliceHandler.reply(for: .accepted("длинная реплика про рефакторинг очередей"))
        #expect(r.response.text == "Передал.")
        #expect(!r.response.text.contains("рефакторинг"))
        #expect(r.response.end_session == false)
    }

    @Test("сессия не закрывается ни на одном исходе — можно говорить дальше")
    func sessionStaysOpen() {
        for outcome in [AliceOutcome.greeting, .accepted("тест"), .empty] {
            #expect(AliceHandler.reply(for: outcome).response.end_session == false)
        }
    }

    @Test("ответ обрезается по лимиту Диалогов")
    func capsReplyLength() {
        let long = String(repeating: "я", count: 3000)
        let r = AliceResponse(text: long, tts: long)
        #expect(r.response.text.count == 1024)
        #expect(r.response.tts?.count == 1024)
    }

    @Test("версия протокола проставляется")
    func setsProtocolVersion() {
        #expect(AliceResponse(text: "ок").version == "1.0")
    }

    @Test("разбирается настоящий запрос Диалогов со всеми полями")
    func decodesRealPayload() throws {
        // Тело как его шлёт платформа — с полями, которых мы не ждём.
        let json = """
        {
          "meta": { "locale": "ru-RU", "timezone": "Europe/Moscow",
                    "client_id": "ru.yandex.quasar/1.0", "interfaces": {} },
          "session": { "message_id": 0, "session_id": "abc", "skill_id": "skill-1",
                       "user_id": "U", "new": true,
                       "user": { "user_id": "U" },
                       "application": { "application_id": "A" } },
          "request": { "command": "какой статус", "original_utterance": "какой статус",
                       "nlu": { "tokens": ["какой","статус"], "entities": [] },
                       "markup": { "dangerous_context": false },
                       "type": "SimpleUtterance" },
          "state": { "session": {} },
          "version": "1.0"
        }
        """
        let decoded = try JSONDecoder().decode(AliceRequest.self, from: Data(json.utf8))
        #expect(decoded.session.skill_id == "skill-1")
        #expect(AliceHandler.decide(decoded) == .accepted("какой статус"))
    }
}
