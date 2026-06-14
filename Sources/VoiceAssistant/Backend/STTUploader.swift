import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Server-side STT response for POST /v1/voice/audio. Mirrors the wire shape
/// described in specs/backend-protocol.md.
public struct STTResponse: Sendable, Equatable {
    public let text: String
    public let lang: String
    public let durationS: Double
    public let sttMs: Int
    public let sttEngine: String
    public let sttSource: String

    public init(
        text: String,
        lang: String,
        durationS: Double,
        sttMs: Int,
        sttEngine: String,
        sttSource: String
    ) {
        self.text = text
        self.lang = lang
        self.durationS = durationS
        self.sttMs = sttMs
        self.sttEngine = sttEngine
        self.sttSource = sttSource
    }
}

/// Errors surfaced to the UI when uploading audio to the STT endpoint.
/// Each case maps from a specific backend failure mode in
/// specs/backend-protocol.md.
public enum STTUploaderError: Error, Sendable, Equatable {
    case unauthorized
    case unsupportedFormat
    case audioTooShort
    case audioTooLong
    case sttUnavailable
    case sttTimeout
    case backendUnavailable
    case network(String)
    case malformedResponse(String)
}

/// Contract every STT uploader honors. UI layer never knows whether audio
/// goes to a real backend, a fake, or a future direct-WhisperKit path —
/// it depends only on this protocol.
public protocol STTUploader: Sendable {
    func upload(audio: Data, clientId: String, ts: Date) async throws -> STTResponse
}

/// Production STTUploader. Sends multipart/form-data POST to
/// `{baseURL}/v1/voice/audio` with Bearer auth.
public struct LiveSTTUploader: STTUploader {
    public let baseURL: URL
    public let token: String
    public let session: URLSession
    public let boundary: String

    public init(
        baseURL: URL,
        token: String,
        session: URLSession = .shared,
        boundary: String? = nil
    ) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.boundary = boundary ?? "voiceassistant-\(UUID().uuidString)"
    }

    public func upload(audio: Data, clientId: String, ts: Date) async throws -> STTResponse {
        let url = baseURL.appendingPathComponent("/v1/voice/audio")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(audio: audio, clientId: clientId, ts: ts)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw STTUploaderError.sttTimeout
            }
            throw STTUploaderError.network(urlError.localizedDescription)
        } catch {
            throw STTUploaderError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw STTUploaderError.malformedResponse("not http")
        }

        switch http.statusCode {
        case 200:
            return try decodeSuccess(data: data)
        case 401:
            throw STTUploaderError.unauthorized
        case 400:
            throw try decode400(data: data)
        case 503:
            throw STTUploaderError.sttUnavailable
        case 504:
            throw STTUploaderError.sttTimeout
        case 502, 500...599:
            throw STTUploaderError.backendUnavailable
        default:
            throw STTUploaderError.malformedResponse("unexpected HTTP \(http.statusCode)")
        }
    }

    // MARK: - Multipart body

    func buildMultipartBody(audio: Data, clientId: String, ts: Date) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        let isoTs = ISO8601DateFormatter.fractionalSeconds.string(from: ts)

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"audio\"; filename=\"rec.caf\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(audio)
        append("\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"client_id\"\r\n\r\n")
        append("\(clientId)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"ts\"\r\n\r\n")
        append("\(isoTs)\r\n")

        append("--\(boundary)--\r\n")
        return body
    }

    // MARK: - Response decoding

    private func decodeSuccess(data: Data) throws -> STTResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw STTUploaderError.malformedResponse("invalid JSON")
        }
        guard
            let text = json["text"] as? String,
            let lang = json["lang"] as? String,
            let durationS = json["duration_s"] as? Double,
            let sttMs = json["stt_ms"] as? Int,
            let sttEngine = json["stt_engine"] as? String,
            let sttSource = json["stt_source"] as? String
        else {
            throw STTUploaderError.malformedResponse("missing required fields")
        }
        return STTResponse(
            text: text, lang: lang, durationS: durationS,
            sttMs: sttMs, sttEngine: sttEngine, sttSource: sttSource
        )
    }

    private func decode400(data: Data) throws -> STTUploaderError {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let error = json?["error"] as? String ?? ""
        switch error {
        case "unsupported_format": return .unsupportedFormat
        case "audio_too_short":    return .audioTooShort
        case "audio_too_long":     return .audioTooLong
        case "missing_field":      return .malformedResponse("server expected field missing in request")
        default:                   return .malformedResponse("400 with unknown error: \(error)")
        }
    }
}

private extension ISO8601DateFormatter {
    static let fractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
