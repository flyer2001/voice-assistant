import Foundation
import Testing
@testable import VoiceServiceCore

@Suite("SmartHomeState — состояние виртуальной лампочки")
struct SmartHomeStateTests {

    private func tempFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("smart-home-\(UUID().uuidString).json")
    }

    @Test("состояние переживает перезапуск")
    func statePersists() {
        let file = tempFile()
        let state = SmartHomeState(path: file)
        #expect(state.isOn == false, "по умолчанию погашена")

        state.set(on: true)
        // Новый экземпляр — как будто сервис перезапустили.
        #expect(SmartHomeState(path: file).isOn == true)

        state.set(on: false)
        #expect(SmartHomeState(path: file).isOn == false)
    }

    @Test("отдаём сохранённое состояние, а не вычисленное")
    func reportsStoredState() {
        // Review Focus №1: Яндекс опрашивает состояние в любой момент, в том
        // числе через миллисекунды после гашения. Если считать «горит ли
        // сейчас» по времени последнего сигнала, опрос соврёт.
        let state = SmartHomeState(path: tempFile())
        state.set(on: true)
        state.set(on: false)
        #expect(state.isOn == false)
        #expect(state.lastChanged.timeIntervalSinceNow > -5, "дата обновилась")
    }

    @Test("битый файл состояния не роняет сервис")
    func survivesCorruptFile() throws {
        let file = tempFile()
        try "это не json".write(to: file, atomically: true, encoding: .utf8)
        let state = SmartHomeState(path: file)
        #expect(state.isOn == false, "откатываемся к погашенной")
        state.set(on: true)
        #expect(SmartHomeState(path: file).isOn == true, "файл перезаписался")
    }
}
