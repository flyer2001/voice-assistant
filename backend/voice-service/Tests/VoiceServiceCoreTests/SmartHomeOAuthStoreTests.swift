import Foundation
import Testing
@testable import VoiceServiceCore

@Suite("OAuthStore — связка аккаунта для навыка умного дома")
struct SmartHomeOAuthStoreTests {

    private func store(login: String = "sergey", password: String = "s3cret") -> OAuthStore {
        OAuthStore(
            path: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("oauth-\(UUID().uuidString).json"),
            login: login,
            password: password,
            clientId: "yandex",
            clientSecret: "client-s3cret"
        )
    }

    @Test("верный логин даёт код, неверный — нет")
    func issuesCodeOnlyForValidLogin() {
        let s = store()
        #expect(s.issueCode(login: "sergey", password: "s3cret") != nil)
        #expect(s.issueCode(login: "sergey", password: "wrong") == nil)
        #expect(s.issueCode(login: "someone", password: "s3cret") == nil)
    }

    @Test("код обменивается на токен ровно один раз")
    func codeIsSingleUse() {
        let s = store()
        let code = s.issueCode(login: "sergey", password: "s3cret")!
        let token = s.exchange(code: code, clientId: "yandex", clientSecret: "client-s3cret")
        #expect(token != nil)
        #expect(s.exchange(code: code, clientId: "yandex", clientSecret: "client-s3cret") == nil,
                "повторный обмен того же кода запрещён")
    }

    @Test("чужой client_secret токен не получит")
    func rejectsWrongClient() {
        let s = store()
        let code = s.issueCode(login: "sergey", password: "s3cret")!
        #expect(s.exchange(code: code, clientId: "yandex", clientSecret: "подобранный") == nil)
    }

    @Test("выданный токен признаётся, чужой — нет")
    func validatesToken() {
        let s = store()
        let code = s.issueCode(login: "sergey", password: "s3cret")!
        let token = s.exchange(code: code, clientId: "yandex", clientSecret: "client-s3cret")!
        #expect(s.isValid(token: token.accessToken) == true)
        #expect(s.isValid(token: "подобранный") == false)
    }

    @Test("токен переживает перезапуск, отвязка его убивает")
    func tokenPersistsAndUnlinks() {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("oauth-\(UUID().uuidString).json")
        let make = {
            OAuthStore(path: path, login: "sergey", password: "s3cret",
                       clientId: "yandex", clientSecret: "client-s3cret")
        }
        let first = make()
        let code = first.issueCode(login: "sergey", password: "s3cret")!
        let token = first.exchange(code: code, clientId: "yandex",
                                   clientSecret: "client-s3cret")!

        #expect(make().isValid(token: token.accessToken) == true, "после рестарта связка жива")

        // Review Focus №4: после отвязки стучать callback'ом нельзя, а значит
        // и токен считать действительным тоже.
        first.unlink()
        #expect(first.isValid(token: token.accessToken) == false)
        #expect(make().isValid(token: token.accessToken) == false)
    }

    @Test("файл с токеном недоступен другим пользователям")
    func tokenFileIsPrivate() throws {
        // Замечание из аудита agentops 04.10: файл лежал с правами 644, то
        // есть токен связки читался любым пользователем VDS.
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("oauth-\(UUID().uuidString).json")
        let s = OAuthStore(path: path, login: "sergey", password: "s3cret",
                           clientId: "yandex", clientSecret: "client-s3cret")
        let code = s.issueCode(login: "sergey", password: "s3cret")!
        _ = s.exchange(code: code, clientId: "yandex", clientSecret: "client-s3cret")

        let perms = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions]
        #expect((perms as? NSNumber)?.int16Value == 0o600,
                "токен должен быть доступен только владельцу процесса")
    }

    @Test("истёкший токен не признаётся")
    func rejectsExpiredToken() {
        let s = store()
        let code = s.issueCode(login: "sergey", password: "s3cret")!
        let token = s.exchange(code: code, clientId: "yandex",
                               clientSecret: "client-s3cret")!
        #expect(s.isValid(token: token.accessToken, now: Date().addingTimeInterval(400 * 86400))
                == false, "через год токен мёртв")
    }
}
