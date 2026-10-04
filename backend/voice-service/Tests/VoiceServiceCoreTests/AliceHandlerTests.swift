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

    @Test("поверхность узнаётся по client_id")
    func surfaceFromClientId() {
        // Метатег src был жёсткой строкой «alice-station», пока других
        // поверхностей не было. Теперь реплика приходит и с телефона, и
        // различать их важно: «запиши мысль» дома и в метро — разный контекст.
        #expect(AliceHandler.surface("ru.yandex.quasar.app/1.0 (Yandex Station)")
                == "alice-station")
        #expect(AliceHandler.surface("aliced/1.0 (Yandex Station Lite)") == "alice-station")
        // Живой client_id Станции Стрит, снят 04.10. «mango» — кодовое имя
        // модели: по нему при надобности различим Стрит и Лайт.
        #expect(AliceHandler.surface("aliced/1.0 (Yandex mango; Linux 1.0)")
                == "alice-station")
        #expect(AliceHandler.surface("ru.yandex.searchplugin/7.16 (iPhone; iOS 18)")
                == "alice-phone")
        #expect(AliceHandler.surface("ru.yandex.mobile.search/1.0") == "alice-phone")
        #expect(AliceHandler.surface("yandex.browser/24.1") == "alice-browser")
        // Живой client_id приложения «Дом с Алисой», снят 04.10 с iPhone.
        // Ни searchplugin, ни quasar — на нём матчер и дал unknown.
        #expect(AliceHandler.surface("com.yandex.iot/12618.0 (Apple iot_app_ios; iphone iOS 26.6.2)")
                == "alice-phone")
        // Неизвестное не выдумываем: пусть будет видно, что не разобрали.
        #expect(AliceHandler.surface("какой-то новый клиент") == "alice-unknown")
        #expect(AliceHandler.surface(nil) == "alice-unknown")
    }

    @Test("«дай ответ» — это запрос готового ответа, а не реплика в сессию")
    func answerRequestRecognised() {
        for phrase in ["дай ответ", "Дай ответ.", "дай ответ пожалуйста",
                       "ответ", "прочитай ответ", "какой ответ"] {
            #expect(AliceHandler.decide(req(command: phrase)) == .answerRequest,
                    "«\(phrase)» должно читаться как запрос ответа")
        }
    }

    @Test("активационное имя в команде не мешает узнать запрос ответа")
    func answerRequestWithLeakedActivationName() {
        // Живой случай 2026-10-02: Алиса прислала команду целиком, вместе с
        // «попроси личного ассистента». Матчер по началу строки её не узнал.
        for phrase in ["попроси личного ассистента дать ответ",
                       "скажи личному ассистенту дай ответ",
                       "передай ассистенту дай ответ",
                       "личный ассистент дай ответ",
                       "ассистента дай ответ",
                       "дать ответ"] {
            #expect(AliceHandler.decide(req(command: phrase)) == .answerRequest,
                    "«\(phrase)» должно читаться как запрос ответа")
        }
    }

    @Test("реплика из одних служебных слов не инжектится")
    func activationNoiseOnly() {
        // Живой случай: Sergey сказал «Алиса», запнулся, пауза обрубила фразу —
        // и в сессию уехало слово «алиса» как мысль.
        for phrase in ["алиса", "Алиса, попроси", "личного ассистента"] {
            #expect(AliceHandler.decide(req(command: phrase)) == .empty,
                    "«\(phrase)» — ничего не сказано, инжектить нечего")
        }
    }

    @Test("обычная реплика со словом «ответ» остаётся репликой")
    func answerWordAloneIsNotRequest() {
        // Иначе диктовка «запиши мысль про ответы сервиса» уедет в чтение
        // ящика вместо инжекта.
        for phrase in ["запиши мысль про ответы сервиса",
                       "переведи слово ответ на английский"] {
            #expect(AliceHandler.decide(req(command: phrase)) == .accepted(phrase),
                    "«\(phrase)» должно уйти в сессию")
        }
    }

    @Test("ответ из ящика озвучивается, пустой ящик — так и говорим")
    func answerReplyRendering() {
        let withText = AliceHandler.answerReply(
            AliceAnswer(text: "horse genital diagnostics", isRepeat: false, isPending: false))
        #expect(withText.response.text == "horse genital diagnostics")
        #expect(withText.response.tts == "horse genital diagnostics")
        #expect(withText.response.end_session == false)

        let empty = AliceHandler.answerReply(nil)
        #expect(empty.response.text.contains("пока нет"))
        #expect(empty.response.end_session == false)
    }

    @Test("«дальше» листает очередь той же командой, что «дай ответ»")
    func nextIsAnswerRequest() {
        // Отдельной машинерии не нужно: листание — это запрос следующего
        // сообщения. Разница только в том, что произносить короче.
        for phrase in ["дальше", "Дальше.", "следующее", "что ещё",
                       "попроси личного ассистента дальше"] {
            #expect(AliceHandler.decide(req(command: phrase)) == .answerRequest,
                    "«\(phrase)» должно листать очередь")
        }
    }

    @Test("«повтори» переслушивает, а не листает очередь")
    func repeatIsItsOwnCommand() {
        for phrase in ["повтори", "Повтори.", "повтори ответ", "ещё раз",
                       "попроси личного ассистента повтори"] {
            #expect(AliceHandler.decide(req(command: phrase)) == .repeatRequest,
                    "«\(phrase)» должно переслушивать последнее")
        }
        // «дальше» по-прежнему листает — команды не должны слиться.
        #expect(AliceHandler.decide(req(command: "дальше")) == .answerRequest)
    }

    @Test("«очисти» выбрасывает очередь")
    func clearCommand() {
        for phrase in ["очисти", "очисти очередь", "забудь всё", "удали все сообщения"] {
            #expect(AliceHandler.decide(req(command: phrase)) == .clearRequest,
                    "«\(phrase)» должно чистить очередь")
        }
        // Диктовка про удаление остаётся репликой, а не командой.
        #expect(AliceHandler.decide(req(command: "запиши мысль удалить старый код"))
                == .accepted("запиши мысль удалить старый код"))
    }

    @Test("после очистки говорим, сколько выбросили")
    func clearReply() {
        #expect(AliceHandler.clearReply(removed: 3).response.text.contains("три"))
        #expect(AliceHandler.clearReply(removed: 1).response.text.contains("одно"))
        let empty = AliceHandler.clearReply(removed: 0)
        #expect(empty.response.text.contains("пуст"))
    }

    @Test("хвост говорит, сколько сообщений осталось")
    func answerReplyTail() {
        let two = AliceHandler.answerReply(
            AliceAnswer(text: "от авито: слой ждёт коммита", isRepeat: false, remaining: 2))
        #expect(two.response.text.contains("ещё два"))
        #expect(two.response.text.contains("дальше"))

        let one = AliceHandler.answerReply(
            AliceAnswer(text: "одно дело", isRepeat: false, remaining: 1))
        #expect(one.response.text.contains("ещё одно"))

        let last = AliceHandler.answerReply(
            AliceAnswer(text: "последнее", isRepeat: false, remaining: 0))
        #expect(!last.response.text.contains("ещё"), "хвоста быть не должно")
    }

    @Test("вопрос новее ответа — говорим, что ответ готовится")
    func answerReplyPending() {
        // Живая путаница 2026-10-02: «повторяю ответ» звучало и когда ответ
        // ещё в работе, и когда нового не будет вовсе. Человек эти случаи не
        // различал и решил, что канал сломан.
        let pendingWithOld = AliceHandler.answerReply(
            AliceAnswer(text: "старый ответ", isRepeat: true, isPending: true))
        #expect(pendingWithOld.response.text.contains("готовится"))
        #expect(pendingWithOld.response.text.contains("старый ответ"),
                "прошлый ответ всё равно отдаём — вдруг человек его и ждал")

        let pendingEmpty = AliceHandler.answerReply(
            AliceAnswer(text: "", isRepeat: false, isPending: true))
        #expect(pendingEmpty.response.text.contains("готовится"))
        #expect(!pendingEmpty.response.text.contains("пока нет"),
                "«ответа нет» и «ответ готовится» — разные вещи")
    }

    @Test("повторный запрос того же ответа предупреждает, что это повтор")
    func answerReplyRepeat() {
        // Ящик не одноразовый: человек мог не расслышать. Но повтор обязан
        // звучать как повтор, иначе старый ответ сойдёт за ответ на новый
        // вопрос.
        let again = AliceHandler.answerReply(
            AliceAnswer(text: "horse genital diagnostics", isRepeat: true, isPending: false))
        #expect(again.response.text.hasPrefix("Повторяю ответ:"))
        #expect(again.response.text.contains("horse genital diagnostics"))
        #expect(again.response.tts?.hasPrefix("Повторяю ответ:") == true)
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
