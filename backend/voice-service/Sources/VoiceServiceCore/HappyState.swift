import Foundation

/// Models for ~/.happy/access.key and ~/.happy/sessions.json. Only the
/// fields needed by inject — extra keys are ignored.

public struct HappyAccessKey: Codable, Sendable {
    public let token: String
}

public struct HappySessionMetadata: Codable, Sendable {
    public let path: String?
    public let lifecycleState: String?
    public let lifecycleStateSince: Double?
}

public struct HappySessionRecord: Codable, Sendable {
    public let encryptionVariant: String?
    public let encryptionKey: String?  // base64, 32 bytes
    public let metadata: HappySessionMetadata?
}

public struct HappySessionsFile: Codable, Sendable {
    public let sessions: [String: HappySessionRecord]
}

public enum HappyStateError: Error, Equatable {
    case accessKeyMissing(String)
    case sessionsFileMissing(String)
    case sessionsFileMalformed(String)
    case noRunningSessionForCwd(String)
    case unsupportedEncryptionVariant(String)
}

/// Reads Happy state files and picks an active session by cwd.
public struct HappyState: Sendable {
    public let happyHome: URL

    public init(happyHome: URL) {
        self.happyHome = happyHome
    }

    public static let defaultHome: URL = {
        let env = ProcessInfo.processInfo.environment["HAPPY_HOME_DIR"]
        if let env, !env.isEmpty {
            let expanded = (env as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        return URL(fileURLWithPath: (("~/.happy" as NSString).expandingTildeInPath))
    }()

    public func readToken() throws -> String {
        let url = happyHome.appendingPathComponent("access.key")
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw HappyStateError.accessKeyMissing(url.path)
        }
        let key = try JSONDecoder().decode(HappyAccessKey.self, from: data)
        return key.token
    }

    public func readSessions() throws -> [String: HappySessionRecord] {
        let url = happyHome.appendingPathComponent("sessions.json")
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw HappyStateError.sessionsFileMissing(url.path)
        }
        do {
            let file = try JSONDecoder().decode(HappySessionsFile.self, from: data)
            return file.sessions
        } catch {
            throw HappyStateError.sessionsFileMalformed(error.localizedDescription)
        }
    }

    /// Pick the most recently-active session with metadata.path == cwd and
    /// lifecycleState == "running". Mirrors inject.mjs pickSession with --to-cwd.
    public func pickRunningSession(byCwd cwd: String, sessions: [String: HappySessionRecord]) throws -> (sid: String, record: HappySessionRecord) {
        let candidates = sessions.filter { _, rec in
            rec.metadata?.path == cwd && rec.metadata?.lifecycleState == "running"
        }
        guard !candidates.isEmpty else {
            throw HappyStateError.noRunningSessionForCwd(cwd)
        }
        let sorted = candidates.sorted { a, b in
            (a.value.metadata?.lifecycleStateSince ?? 0) > (b.value.metadata?.lifecycleStateSince ?? 0)
        }
        let pick = sorted[0]
        return (pick.key, pick.value)
    }
}
