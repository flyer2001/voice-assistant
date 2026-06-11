import Foundation
import Testing
@testable import VoiceServiceCore

@Suite("HappyState — reads access.key + sessions.json, picks by cwd")
struct HappyStateTests {

    /// Writes a minimal Happy home with given access.key + sessions.json contents.
    func makeTempHome(token: String?, sessionsJSON: String?) throws -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("happy-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if let token {
            let keyJSON = "{\"token\":\"\(token)\"}"
            try keyJSON.write(to: home.appendingPathComponent("access.key"), atomically: true, encoding: .utf8)
        }
        if let sessionsJSON {
            try sessionsJSON.write(to: home.appendingPathComponent("sessions.json"), atomically: true, encoding: .utf8)
        }
        return home
    }

    @Test("readToken returns token from access.key")
    func readToken() throws {
        let home = try makeTempHome(token: "abc123", sessionsJSON: nil)
        let state = HappyState(happyHome: home)
        #expect(try state.readToken() == "abc123")
    }

    @Test("readToken throws if access.key missing")
    func tokenMissing() throws {
        let home = try makeTempHome(token: nil, sessionsJSON: nil)
        let state = HappyState(happyHome: home)
        #expect(throws: HappyStateError.self) {
            _ = try state.readToken()
        }
    }

    @Test("pickRunningSession picks most recent running session by cwd")
    func pickByCwd() throws {
        let json = """
        {"sessions":{
            "sid-old":{"encryptionVariant":"dataKey","encryptionKey":"AAAA","metadata":{"path":"/root/projects/cashflow","lifecycleState":"running","lifecycleStateSince":1000}},
            "sid-new":{"encryptionVariant":"dataKey","encryptionKey":"BBBB","metadata":{"path":"/root/projects/cashflow","lifecycleState":"running","lifecycleStateSince":2000}},
            "sid-stopped":{"encryptionVariant":"dataKey","encryptionKey":"CCCC","metadata":{"path":"/root/projects/cashflow","lifecycleState":"stopped","lifecycleStateSince":3000}},
            "sid-other":{"encryptionVariant":"dataKey","encryptionKey":"DDDD","metadata":{"path":"/root/projects/voice","lifecycleState":"running","lifecycleStateSince":2500}}
        }}
        """
        let home = try makeTempHome(token: "t", sessionsJSON: json)
        let state = HappyState(happyHome: home)
        let sessions = try state.readSessions()
        let picked = try state.pickRunningSession(byCwd: "/root/projects/cashflow", sessions: sessions)
        #expect(picked.sid == "sid-new", "should pick most recent running session")
    }

    @Test("pickRunningSession throws when no running session for cwd")
    func noRunning() throws {
        let json = """
        {"sessions":{
            "sid-stopped":{"encryptionVariant":"dataKey","encryptionKey":"AAAA","metadata":{"path":"/root/projects/cashflow","lifecycleState":"stopped","lifecycleStateSince":1000}}
        }}
        """
        let home = try makeTempHome(token: "t", sessionsJSON: json)
        let state = HappyState(happyHome: home)
        let sessions = try state.readSessions()
        #expect(throws: HappyStateError.self) {
            _ = try state.pickRunningSession(byCwd: "/root/projects/cashflow", sessions: sessions)
        }
    }
}
