import Foundation
import AsyncHTTPClient
import NIOCore
import NIOFoundationCompat
import NIOHTTP1

/// HTTP relay to a FastAPI Whisper server (faster-whisper on Win-CUDA per
/// REPORT-2026-06-10.md: WER 30%, ~447ms baseline). Forwards multipart audio,
/// returns an `STTResult` already shaped for `STTProvider`.
///
/// Built on AsyncHTTPClient (not URLSession) — URLSession.shared in a captured
/// closure inside Hummingbird's async handler context crashes the Swift runtime
/// on macOS 26.4 (EXC_BAD_ACCESS in type metadata accessor for Application).
/// AsyncHTTPClient works cleanly; see spike: hb-spike 2026-06-14.
public struct WhisperHTTPRelay: Sendable {
    public let baseURL: String
    public let timeout: TimeAmount

    public init(baseURL: String, timeout: TimeAmount = .seconds(30)) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.timeout = timeout
    }

    public func transcribe(audio: Data, langHint: String = "") async throws -> STTResult {
        let boundary = "voice-svc-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"audio\"; filename=\"rec.caf\"\r\n".utf8))
        body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"lang_hint\"\r\n\r\n".utf8))
        body.append(Data("\(langHint)\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = HTTPClientRequest(url: "\(baseURL)/transcribe")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "multipart/form-data; boundary=\(boundary)")
        request.body = .bytes(body)

        let response = try await HTTPClient.shared.execute(request, timeout: timeout)
        guard response.status == .ok else {
            let buf = try? await response.body.collect(upTo: 1024 * 4)
            let preview = buf.map { String(buffer: $0).prefix(200) } ?? ""
            throw WhisperRelayError.upstream(status: Int(response.status.code), body: String(preview))
        }
        let buf = try await response.body.collect(upTo: 4 * 1024 * 1024)
        let data = Data(buffer: buf)
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
}

public enum WhisperRelayError: Error, Equatable {
    case transport(String)
    case upstream(status: Int, body: String)
    case malformedResponse(String)
}
