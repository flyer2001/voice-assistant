import Foundation

/// Polls latest `*.jsonl` in `~/.claude/projects/<encoded-cwd>/` and returns
/// the next `type: "assistant"` text message that arrives after `baseline`.
/// Mirrors inject.mjs `waitForReply` (v2 — 500ms polling, re-scan latest per
/// iteration, advance baseline after tail-read).
public struct JsonlWatcher: Sendable {

    public enum Reply: Equatable {
        case message(text: String, jsonlPath: String)
        case timeout(lastJsonlPath: String?)
    }

    public let pollInterval: Duration
    public let claudeProjectsRoot: URL

    public init(
        claudeProjectsRoot: URL = JsonlWatcher.defaultProjectsRoot,
        pollInterval: Duration = .milliseconds(500)
    ) {
        self.claudeProjectsRoot = claudeProjectsRoot
        self.pollInterval = pollInterval
    }

    public static let defaultProjectsRoot: URL = {
        URL(fileURLWithPath: (("~/.claude/projects" as NSString).expandingTildeInPath))
    }()

    /// Claude's encoding: replace `/` with `-` and prepend to projects root.
    public func encodedDir(forCwd cwd: String) -> URL {
        let encoded = cwd.replacingOccurrences(of: "/", with: "-")
        return claudeProjectsRoot.appendingPathComponent(encoded)
    }

    /// Find newest *.jsonl in the encoded dir (by mtime). nil if dir absent
    /// or empty.
    public func findLatestJsonl(forCwd cwd: String) -> URL? {
        let dir = encodedDir(forCwd: cwd)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        let jsonl = entries.filter { $0.pathExtension == "jsonl" }
        guard !jsonl.isEmpty else { return nil }
        let sorted = jsonl.sorted { a, b in
            let aMtime = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let bMtime = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return aMtime > bMtime
        }
        return sorted.first
    }

    public func fileSize(_ url: URL) -> Int {
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attr?[.size] as? Int) ?? 0
    }

    /// Wait for next assistant message after the given baseline size in
    /// `initialJsonl`. If `initialJsonl` is nil, watcher waits for the dir
    /// to appear (cold-start case).
    public func waitForAssistantReply(
        targetCwd: String,
        initialJsonl: URL?,
        baselineSize: Int,
        timeout: Duration
    ) async -> Reply {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var jsonlPath = initialJsonl
        var baseline = baselineSize

        while ContinuousClock.now < deadline {
            // Re-scan latest JSONL — Claude may have spawned a new file
            // (cold-start, post-/endsession resume).
            let freshLatest = findLatestJsonl(forCwd: targetCwd)
            if let freshLatest, freshLatest != jsonlPath {
                jsonlPath = freshLatest
                baseline = 0
            }

            if let jsonlPath {
                let sz = fileSize(jsonlPath)
                if sz > baseline {
                    if let data = try? Data(contentsOf: jsonlPath) {
                        let tailStart = min(baseline, data.count)
                        let tail = data.subdata(in: tailStart..<data.count)
                        if let tailString = String(data: tail, encoding: .utf8) {
                            let lines = tailString.split(separator: "\n", omittingEmptySubsequences: true)
                            for line in lines {
                                if let text = Self.extractAssistantText(from: String(line)) {
                                    return .message(text: text, jsonlPath: jsonlPath.path)
                                }
                            }
                        }
                    }
                    baseline = sz
                }
            }
            try? await Task.sleep(for: pollInterval)
        }
        return .timeout(lastJsonlPath: jsonlPath?.path)
    }

    /// Extract assistant text from a JSONL line. Mirrors inject.mjs
    /// extractAssistantText — handles both `content: "string"` and
    /// `content: [{type:"text", text:"..."}]` shapes.
    public static func extractAssistantText(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String, type == "assistant",
              let message = obj["message"] as? [String: Any]
        else { return nil }

        if let content = message["content"] as? String, !content.isEmpty {
            return content
        }
        if let parts = message["content"] as? [[String: Any]] {
            let texts = parts.compactMap { part -> String? in
                guard (part["type"] as? String) == "text" else { return nil }
                return part["text"] as? String
            }
            return texts.isEmpty ? nil : texts.joined(separator: "\n")
        }
        return nil
    }
}
