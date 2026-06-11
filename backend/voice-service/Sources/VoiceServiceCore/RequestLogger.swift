import Foundation

/// Append-only JSONL request log. One line per /v1/voice/intent request,
/// shape:
///   {"ts":"...", "client_id":"...", "text":"...", "reply":"...", "latency_ms":N, "error":"..."}
///
/// `error` is included only on failure paths. `reply` only on success.
public final class RequestLogger: @unchecked Sendable {

    public let path: URL
    private let queue = DispatchQueue(label: "voice-service.request-logger")
    private let dateFormatter: ISO8601DateFormatter

    public init(path: URL) {
        self.path = path
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dateFormatter = f
        // Ensure parent dir + file exist
        let dir = path.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path.path) {
            FileManager.default.createFile(atPath: path.path, contents: nil)
        }
    }

    public func logSuccess(clientId: String, text: String, reply: String, latencyMs: Int) {
        write([
            "ts": dateFormatter.string(from: Date()),
            "client_id": clientId,
            "text": text,
            "reply": reply,
            "latency_ms": latencyMs,
        ])
    }

    public func logError(clientId: String, text: String, error: String, latencyMs: Int) {
        write([
            "ts": dateFormatter.string(from: Date()),
            "client_id": clientId,
            "text": text,
            "error": error,
            "latency_ms": latencyMs,
        ])
    }

    private func write(_ dict: [String: Any]) {
        queue.sync {
            guard
                let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
                let line = String(data: data, encoding: .utf8)
            else { return }
            let lineWithNewline = line + "\n"
            guard let bytes = lineWithNewline.data(using: .utf8) else { return }
            if let fh = try? FileHandle(forWritingTo: path) {
                try? fh.seekToEnd()
                try? fh.write(contentsOf: bytes)
                try? fh.close()
            }
        }
    }
}
