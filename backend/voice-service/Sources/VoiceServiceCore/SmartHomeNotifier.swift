import Foundation

/// Сигнал на колонку: мигаем виртуальной лампочкой, чтобы сценарий в «Доме
/// с Алисой» проиграл звук.
///
/// Навык не может заговорить первым, а сценарий умного дома — может.
/// Поэтому схема двухтактная: звук будит человека, а текст он забирает
/// командой «дай ответ». План —
/// docs/plans/2026-10-04-alice-smart-home-push.md
public struct SmartHomeNotifier: Sendable {

    let state: SmartHomeState
    /// Текущий токен связки. Nil — навык не привязан или отвязан.
    let accessToken: @Sendable () -> String?
    /// Отправка состояния в платформу, возвращает HTTP-код.
    let postState: @Sendable (_ value: Bool, _ token: String) async -> Int
    let logError: @Sendable (String) -> Void

    public init(state: SmartHomeState,
                accessToken: @escaping @Sendable () -> String?,
                postState: @escaping @Sendable (_ value: Bool, _ token: String) async -> Int,
                logError: @escaping @Sendable (String) -> Void) {
        self.state = state
        self.accessToken = accessToken
        self.postState = postState
        self.logError = logError
    }

    /// Мигнуть лампочкой. Сценарий ловит именно **переход** состояния,
    /// поэтому гасим перед включением: если лампочка осталась включённой с
    /// прошлого сигнала, повторное включение перехода не создаст и звука не
    /// будет.
    public func signal() async {
        guard let token = accessToken() else {
            logError("сигнал не отправлен: нет связки с платформой")
            return
        }

        if state.isOn {
            await send(value: false, token: token)
        }
        await send(value: true, token: token)
        // Гасим сразу: лампочка — это импульс, а не индикатор. Иначе
        // следующий сигнал начнётся с лишнего гашения.
        await send(value: false, token: token)
    }

    private func send(value: Bool, token: String) async {
        state.set(on: value)
        let code = await postState(value, token)
        guard (200..<300).contains(code) else {
            // Молчаливый отказ здесь — худший вид поломки: сигнала нет, а
            // выглядит как рабочая система.
            logError("платформа отклонила сигнал, код \(code), значение \(value)")
            return
        }
    }
}
