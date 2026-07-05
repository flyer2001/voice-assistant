import Foundation
import Testing
@testable import VoiceServiceCore

@Suite("FocusState — Phase 6 F1 focus routing")
struct FocusStateTests {

    func tmpFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focus-\(UUID().uuidString).json")
    }

    func makeHappyHome(sessionsJSON: String) throws -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("happy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "{\"token\":\"t\"}".write(to: home.appendingPathComponent("access.key"), atomically: true, encoding: .utf8)
        try sessionsJSON.write(to: home.appendingPathComponent("sessions.json"), atomically: true, encoding: .utf8)
        return home
    }

    @Test("read missing file returns nil")
    func readMissing() throws {
        let state = FocusState(path: tmpFile())
        #expect(try state.read() == nil)
    }

    @Test("write + read roundtrip")
    func roundtrip() throws {
        let state = FocusState(path: tmpFile())
        let f = Focus(cwd: "/root/projects/cashflow", since: "2026-07-05T10:00:00Z", setByMsg: 42, note: "focus cashflow")
        try state.write(f)
        #expect(try state.read() == f)
    }

    @Test("initIfAbsent creates {cwd: null} then read returns Focus with nil cwd")
    func initEmpty() throws {
        let state = FocusState(path: tmpFile())
        try state.initIfAbsent()
        let f = try state.read()
        #expect(f != nil)
        #expect(f?.cwd == nil)
    }

    @Test("validate nil focus → fallback(no_focus)")
    func validateNoFocus() throws {
        let home = try makeHappyHome(sessionsJSON: "{\"sessions\":{}}")
        let state = FocusState(path: tmpFile())
        let happy = HappyState(happyHome: home)
        #expect(state.validate(nil, happyState: happy) == .fallback(reason: "no_focus"))
        #expect(state.validate(Focus(cwd: nil), happyState: happy) == .fallback(reason: "no_focus"))
    }

    @Test("validate cwd not-a-directory → fallback(cwd_missing)")
    func validateCwdMissing() throws {
        let home = try makeHappyHome(sessionsJSON: "{\"sessions\":{}}")
        let state = FocusState(path: tmpFile())
        let happy = HappyState(happyHome: home)
        let f = Focus(cwd: "/no/such/dir/\(UUID().uuidString)")
        #expect(state.validate(f, happyState: happy) == .fallback(reason: "cwd_missing"))
    }

    @Test("validate session offline → fallback(session_offline)")
    func validateSessionOffline() throws {
        let json = """
        {"sessions":{
            "sid-stopped":{"encryptionVariant":"dataKey","encryptionKey":"AA","metadata":{"path":"/tmp","lifecycleState":"stopped","lifecycleStateSince":1000}}
        }}
        """
        let home = try makeHappyHome(sessionsJSON: json)
        let state = FocusState(path: tmpFile())
        let happy = HappyState(happyHome: home)
        let f = Focus(cwd: "/tmp")
        #expect(state.validate(f, happyState: happy) == .fallback(reason: "session_offline"))
    }

    @Test("validate running session → focus(cwd)")
    func validateFocus() throws {
        let json = """
        {"sessions":{
            "sid-run":{"encryptionVariant":"dataKey","encryptionKey":"AA","metadata":{"path":"/tmp","lifecycleState":"running","lifecycleStateSince":2000}}
        }}
        """
        let home = try makeHappyHome(sessionsJSON: json)
        let state = FocusState(path: tmpFile())
        let happy = HappyState(happyHome: home)
        let f = Focus(cwd: "/tmp")
        #expect(state.validate(f, happyState: happy) == .focus(cwd: "/tmp"))
    }
}
