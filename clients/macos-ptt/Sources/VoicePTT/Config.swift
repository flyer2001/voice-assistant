import Foundation

struct Config: Codable {
    let backendURL: URL
    let backendToken: String
    let clientId: String
    // F19 = 80. F13 = 105. CapsLock via Karabiner→F19 = 80.
    let hotkeyCode: UInt16
    // Скажет transcript через `say`. False = только уведомление.
    let speakReply: Bool
    // TTS voice для `say` (Russian: Yuri, Milena; English: Samantha).
    let sayVoice: String?

    static func load() throws -> Config {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".voice-ptt/config.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    }
}
