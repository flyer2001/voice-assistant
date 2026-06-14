import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP relay to a FastAPI Whisper server (faster-whisper on Win-CUDA per
/// REPORT-2026-06-10.md: WER 30%, ~447ms baseline). Forwards multipart audio,
/// returns an `STTResult` already shaped for `STTProvider`.
public struct WhisperHTTPRelay: Sendable {
    public let baseURL: URL
    public let session: URLSession
    public let timeout: TimeInterval

    public init(baseURL: URL, session: URLSession = .shared, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    public func transcribe(audio: Data, langHint: String = "") async throws -> STTResult {
        // URL.appendingPathComponent crashes on macOS 26.4 with deprecated impl —
        // build the URL via string concat instead.
        let trimmed = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        guard let url = URL(string: "\(trimmed)/transcribe") else {
            throw WhisperRelayError.transport("invalid url")
        }
        let boundary = "voice-svc-\(UUID().uuidString)"
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildBody(audio: audio, langHint: langHint, boundary: boundary)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WhisperRelayError.transport("non-http response")
        }
        guard http.statusCode == 200 else {
            throw WhisperRelayError.upstream(status: http.statusCode, body: previewBody(data))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WhisperRelayError.malformedResponse("invalid JSON")
        }
        let text = json["text"] as? String ?? ""
        let lang = json["lang"] as? String ?? "ru"
        let durationS = json["duration_s"] as? Double ?? 0
        let sttMs = (json["stt_ms"] as? Int) ?? Int((json["stt_ms"] as? Double) ?? 0)
        return STTResult(
            text: text,
            lang: lang,
            durationS: durationS,
            sttMs: sttMs,
            sttEngine: "whisper-large-v3-turbo",
            sttSource: "win-home"
        )
    }

    func buildBody(audio: Data, langHint: String, boundary: String) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"audio\"; filename=\"rec.caf\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(audio)
        append("\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"lang_hint\"\r\n\r\n")
        append("\(langHint)\r\n")
        append("--\(boundary)--\r\n")
        return body
    }

    private func previewBody(_ data: Data) -> String {
        let str = String(data: data, encoding: .utf8) ?? ""
        return String(str.prefix(200))
    }
}

public enum WhisperRelayError: Error, Equatable {
    case transport(String)
    case upstream(status: Int, body: String)
    case malformedResponse(String)
}
