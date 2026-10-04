import Foundation
import Testing
@testable import VoiceServiceCore

@Suite("SmartHomeNotifier — сигнал на колонку через callback")
struct SmartHomeNotifierTests {

    /// Куда сложились отправленные callback'и вместо сети.
    final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(value: Bool, token: String)] = []
        /// Чем ответит платформа. 200 — успех, 401 — отвязано или истекло.
        var status = 200
        func record(_ value: Bool, _ token: String) -> Int {
            lock.lock(); defer { lock.unlock() }
            items.append((value, token))
            return status
        }
        var values: [Bool] { lock.lock(); defer { lock.unlock() }; return items.map(\.value) }
        var tokens: [String] { lock.lock(); defer { lock.unlock() }; return items.map(\.token) }
    }

    /// Журнал ошибок: отказ callback'а обязан быть видимым, иначе сигнал
    /// пропадает молча (Review Focus №3).
    final class Errors: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func makeNotifier(sent: Sent, errors: Errors,
                              state: SmartHomeState,
                              token: String? = "tok-1") -> SmartHomeNotifier {
        SmartHomeNotifier(
            state: state,
            accessToken: { token },
            postState: { value, token in sent.record(value, token) },
            logError: { errors.add($0) }
        )
    }

    private func freshState() -> SmartHomeState {
        SmartHomeState(path: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("st-\(UUID().uuidString).json"))
    }

    @Test("сигнал даёт переход состояния: включили, затем погасили")
    func signalTogglesOnThenOff() async {
        let sent = Sent(), errors = Errors(), state = freshState()
        await makeNotifier(sent: sent, errors: errors, state: state).signal()
        #expect(sent.values == [true, false], "сценарий ловит именно переход")
        #expect(state.isOn == false, "после сигнала лампочка погашена")
        #expect(errors.all.isEmpty)
    }

    @Test("второй сигнал при горящей лампочке всё равно даёт переход")
    func secondSignalStillTransitions() async {
        // Review Focus №2: если лампочка осталась включённой, повторное
        // включение перехода не создаёт и сценарий промолчит. Гасим до.
        let sent = Sent(), errors = Errors(), state = freshState()
        state.set(on: true)
        await makeNotifier(sent: sent, errors: errors, state: state).signal()
        #expect(sent.values.first == false, "сначала гасим")
        #expect(sent.values.contains(true), "потом включаем — есть переход")
        #expect(sent.values.last == false)
    }

    @Test("callback подписывается текущим токеном")
    func usesCurrentToken() async {
        let sent = Sent(), errors = Errors()
        await makeNotifier(sent: sent, errors: errors, state: freshState(),
                           token: "tok-42").signal()
        #expect(sent.tokens.allSatisfy { $0 == "tok-42" })
    }

    @Test("нет связки — не стучим и говорим об этом в журнал")
    func noTokenNoCall() async {
        // Review Focus №4: после отвязки аккаунта стучать нельзя.
        let sent = Sent(), errors = Errors()
        await makeNotifier(sent: sent, errors: errors, state: freshState(),
                           token: nil).signal()
        #expect(sent.values.isEmpty)
        #expect(errors.all.count == 1)
        #expect(errors.all[0].contains("связк"), "причина названа, а не просто «ошибка»")
    }

    @Test("отказ платформы попадает в журнал, а не теряется")
    func failureIsLogged() async {
        // Review Focus №3: истёкший токен даёт 401, и сигнал пропадает.
        // Молчаливый отказ здесь — худший вид поломки.
        let sent = Sent(), errors = Errors()
        sent.status = 401
        await makeNotifier(sent: sent, errors: errors, state: freshState()).signal()
        #expect(!errors.all.isEmpty)
        #expect(errors.all.contains { $0.contains("401") }, "код ответа назван")
    }
}
