import Foundation
import Testing
@testable import VoiceServiceCore

@Suite("JsonlWatcher — find latest + extract assistant text + wait")
struct JsonlWatcherTests {

    func makeTempProjectsRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watcher-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("encodedDir encodes cwd by replacing / with -")
    func encodedDir() throws {
        let root = try makeTempProjectsRoot()
        let watcher = JsonlWatcher(claudeProjectsRoot: root)
        let dir = watcher.encodedDir(forCwd: "/root/projects/cashflow")
        #expect(dir.lastPathComponent == "-root-projects-cashflow")
    }

    @Test("extractAssistantText returns text for string content")
    func extractString() {
        let line = #"{"type":"assistant","message":{"content":"hello"}}"#
        #expect(JsonlWatcher.extractAssistantText(from: line) == "hello")
    }

    @Test("extractAssistantText returns joined text for array content")
    func extractArray() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"hello"},{"type":"text","text":"world"}]}}"#
        #expect(JsonlWatcher.extractAssistantText(from: line) == "hello\nworld")
    }

    @Test("extractAssistantText returns nil for non-assistant type")
    func extractNilNonAssistant() {
        let line = #"{"type":"user","message":{"content":"hi"}}"#
        #expect(JsonlWatcher.extractAssistantText(from: line) == nil)
    }

    @Test("findLatestJsonl returns newest file by mtime")
    func findLatest() throws {
        let root = try makeTempProjectsRoot()
        let cwd = "/foo/bar"
        let dir = root.appendingPathComponent("-foo-bar")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let older = dir.appendingPathComponent("a.jsonl")
        let newer = dir.appendingPathComponent("b.jsonl")
        try "{}".write(to: older, atomically: true, encoding: .utf8)
        try "{}".write(to: newer, atomically: true, encoding: .utf8)
        // Touch newer to ensure mtime ordering
        let future = Date().addingTimeInterval(10)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: newer.path)
        let watcher = JsonlWatcher(claudeProjectsRoot: root)
        let found = watcher.findLatestJsonl(forCwd: cwd)
        #expect(found?.lastPathComponent == "b.jsonl")
    }

    @Test("waitForAssistantReply picks up appended line within timeout")
    func waitPicksUpLine() async throws {
        let root = try makeTempProjectsRoot()
        let cwd = "/foo/bar"
        let dir = root.appendingPathComponent("-foo-bar")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("session.jsonl")
        // Seed file empty
        try Data().write(to: file)

        let watcher = JsonlWatcher(claudeProjectsRoot: root, pollInterval: .milliseconds(100))

        // Append assistant line after 300ms
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            let line = #"{"type":"assistant","message":{"content":"reply text"}}"# + "\n"
            if let fh = try? FileHandle(forWritingTo: file) {
                try? fh.seekToEnd()
                try? fh.write(contentsOf: Data(line.utf8))
                try? fh.close()
            }
        }

        let reply = await watcher.waitForAssistantReply(
            targetCwd: cwd,
            initialJsonl: file,
            baselineSize: 0,
            timeout: .seconds(3)
        )
        switch reply {
        case .message(let text, _):
            #expect(text == "reply text")
        case .timeout:
            Issue.record("expected message, got timeout")
        }
    }

    @Test("waitForAssistantReply times out when no new content")
    func waitTimesOut() async throws {
        let root = try makeTempProjectsRoot()
        let cwd = "/foo/bar"
        let dir = root.appendingPathComponent("-foo-bar")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("session.jsonl")
        try Data().write(to: file)

        let watcher = JsonlWatcher(claudeProjectsRoot: root, pollInterval: .milliseconds(100))
        let reply = await watcher.waitForAssistantReply(
            targetCwd: cwd,
            initialJsonl: file,
            baselineSize: 0,
            timeout: .milliseconds(400)
        )
        if case .timeout = reply {
            // ok
        } else {
            Issue.record("expected timeout, got \(reply)")
        }
    }
}
