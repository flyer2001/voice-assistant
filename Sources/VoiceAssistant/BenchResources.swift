import Foundation

/// Accessor для аудио-ресурсов бенча, упакованных в VoiceAssistant SPM library.
/// `.process("Resources")` в Package.swift копирует Sources/VoiceAssistant/Resources/audio/{clean,gsm}/*.wav
/// в auto-generated bundle, доступный через `Bundle.module`.
public enum BenchResources {
    public static var audioBundle: Bundle { .module }

    /// Returns все .wav файлы в bundle (filtered to bench files).
    public static func allAudioFiles() -> [URL] {
        let bundle = Self.audioBundle
        var urls: [URL] = []
        for sub in ["audio/clean", "audio/gsm", "clean", "gsm"] {
            if let found = bundle.urls(forResourcesWithExtension: "wav", subdirectory: sub) {
                urls.append(contentsOf: found)
            }
        }
        if urls.isEmpty, let flat = bundle.urls(forResourcesWithExtension: "wav", subdirectory: nil) {
            urls.append(contentsOf: flat)
        }
        return urls
            .filter { name in
                let n = name.lastPathComponent.lowercased()
                return n.contains("quiet") || n.contains("noisy")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
