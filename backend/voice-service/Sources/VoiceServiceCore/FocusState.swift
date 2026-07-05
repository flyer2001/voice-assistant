import Foundation

/// Multi-project voice routing — Phase 6 F1.
///
/// `/var/lib/voice-bot/focus.json`: `{cwd, since, setByMsg, note}` all optional.
/// Missing file OR `cwd == nil` → default target (dispatcher).
/// Single writer (dispatcher via inject), single reader (voice-backend pipeline).

public struct Focus: Codable, Sendable, Equatable {
    public var cwd: String?
    public var since: String?
    public var setByMsg: Int64?
    public var note: String?

    public init(cwd: String? = nil, since: String? = nil, setByMsg: Int64? = nil, note: String? = nil) {
        self.cwd = cwd
        self.since = since
        self.setByMsg = setByMsg
        self.note = note
    }
}

public enum ValidatedTarget: Sendable, Equatable {
    case focus(cwd: String)
    case fallback(reason: String)
}

public enum FocusStateError: Error, Equatable {
    case malformed(String)
}

public struct FocusState: Sendable {
    public let path: URL

    public init(path: URL) {
        self.path = path
    }

    public static let defaultPath = URL(fileURLWithPath: "/var/lib/voice-bot/focus.json")

    /// Returns nil if file missing; throws on malformed JSON.
    public func read() throws -> Focus? {
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            return nil
        }
        do {
            return try JSONDecoder().decode(Focus.self, from: data)
        } catch {
            throw FocusStateError.malformed(error.localizedDescription)
        }
    }

    /// Atomic write — Foundation's `.atomic` writes tmp + rename under the hood.
    public func write(_ focus: Focus) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(focus)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: path, options: .atomic)
    }

    /// Init `{"cwd": null}` if file absent — makes state discoverable via cat.
    public func initIfAbsent() throws {
        if (try? read()) == nil, !FileManager.default.fileExists(atPath: path.path) {
            try write(Focus())
        }
    }

    /// Decide routing target. Fallback reasons: `no_focus`, `cwd_missing`, `session_offline`.
    public func validate(_ focus: Focus?, happyState: HappyState) -> ValidatedTarget {
        guard let cwd = focus?.cwd, !cwd.isEmpty else {
            return .fallback(reason: "no_focus")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue else {
            return .fallback(reason: "cwd_missing")
        }
        do {
            let sessions = try happyState.readSessions()
            _ = try happyState.pickRunningSession(byCwd: cwd, sessions: sessions)
            return .focus(cwd: cwd)
        } catch {
            return .fallback(reason: "session_offline")
        }
    }
}
