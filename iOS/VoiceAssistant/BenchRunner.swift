import Foundation
import Speech

/// Skeleton for on-device STT benchmark.
/// Real implementation (5 candidates × N files × M runs → CSV) — следующая итерация.
/// Текущая версия — verify что project builds + Speech framework + WhisperKit linkable.
@MainActor
final class BenchRunner: ObservableObject {
    @Published var isRunning = false
    @Published var log = ""

    func runAll() async {
        isRunning = true
        defer { isRunning = false }

        log = "Bench skeleton ready.\n"
        log += "Build target: iOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        log += "Device: \(deviceModel())\n"
        log += "\nКандидаты для прогона:\n"
        log += "  • SFSpeechRecognizer (iOS 13+)\n"
        if #available(iOS 26.0, *) {
            log += "  • DictationTranscriber (iOS 26 fallback) ✓ available\n"
            log += "  • SpeechTranscriber (iOS 26 new) ✓ available\n"
        } else {
            log += "  • DictationTranscriber — NOT AVAILABLE (need iOS 26+)\n"
            log += "  • SpeechTranscriber — NOT AVAILABLE (need iOS 26+)\n"
        }
        log += "  • WhisperKit base (~150 MB)\n"
        log += "  • WhisperKit small (~480 MB)\n"
        log += "\nNext: bundle 32 audio files + implement transcribe loops.\n"

        // Smoke check: verify Speech framework loads без crash
        _ = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
        log += "\n✓ SFSpeechRecognizer instantiated for ru-RU.\n"
    }

    private func deviceModel() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        return machine
    }
}
