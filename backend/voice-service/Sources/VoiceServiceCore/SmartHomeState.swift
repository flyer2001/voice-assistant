import Foundation

/// Состояние виртуальной лампочки «Уведомление» для навыка умного дома.
///
/// Лампочка ничего не освещает — это переключатель, за который дёргает
/// бэкенд, чтобы сценарий в «Доме с Алисой» проиграл звук на колонке.
/// Подробности: docs/plans/2026-10-04-alice-smart-home-push.md
///
/// Состояние на диске, а не в памяти: Яндекс опрашивает устройство в любой
/// момент, в том числе сразу после рестарта сервиса, и обязан получить то
/// же, что видел до него.
public final class SmartHomeState: @unchecked Sendable {

    private struct Snapshot: Codable {
        var isOn: Bool
        var lastChanged: Date
    }

    private let lock = NSLock()
    private let path: URL
    private var snapshot: Snapshot

    public init(path: URL) {
        self.path = path
        // Битый или отсутствующий файл — не причина падать: файл правит
        // человек. Откатываемся к погашенной лампочке.
        if let data = try? Data(contentsOf: path),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = Snapshot(isOn: false, lastChanged: .distantPast)
        }
    }

    public var isOn: Bool {
        lock.lock(); defer { lock.unlock() }
        return snapshot.isOn
    }

    public var lastChanged: Date {
        lock.lock(); defer { lock.unlock() }
        return snapshot.lastChanged
    }

    public func set(on: Bool) {
        lock.lock(); defer { lock.unlock() }
        snapshot = Snapshot(isOn: on, lastChanged: Date())
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: path, options: .atomic)
        }
    }
}
