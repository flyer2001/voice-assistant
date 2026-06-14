import Foundation
import Hummingbird
import MultipartKit

public enum VoiceServiceApp {
    /// Build an Application configured for tests (`.router` transport) or for
    /// production (`.live` listening on host:port). Caller picks the transport
    /// when invoking `app.test(...)` or `app.run()`.
    public static func make(config: Configuration, host: String = "127.0.0.1", port: Int = 8089) -> some ApplicationProtocol {
        let router = Router()
        router.add(middleware: BearerAuthMiddleware(token: config.token))
        router.post("/v1/voice/audio") { request, context -> Response in
            guard let sttProvider = config.sttProvider else {
                return errorResponse(.serviceUnavailable, error: "stt_unavailable")
            }
            let contentType = request.headers[.contentType] ?? ""
            guard contentType.hasPrefix("multipart/form-data") else {
                return errorResponse(.badRequest, error: "unsupported_format")
            }
            guard let boundary = extractBoundary(from: contentType) else {
                return errorResponse(.badRequest, error: "unsupported_format")
            }

            let body = try await request.body.collect(upTo: 64 * 1024 * 1024)

            let audioReq: AudioMultipartRequest
            do {
                audioReq = try FormDataDecoder().decode(
                    AudioMultipartRequest.self,
                    from: body,
                    boundary: boundary
                )
            } catch {
                return errorResponse(.badRequest, error: "missing_field")
            }

            do {
                let result = try await sttProvider(audioReq.audio, audioReq.client_id)
                let payload = AudioResponseDTO(
                    text: result.text,
                    lang: result.lang,
                    duration_s: result.durationS,
                    stt_ms: result.sttMs,
                    stt_engine: result.sttEngine,
                    stt_source: result.sttSource
                )
                return jsonResponse(.ok, body: payload)
            } catch {
                return errorResponse(.badGateway, error: "stt_failed")
            }
        }
        router.post("/v1/voice/intent") { request, context -> Response in
            let started = Date()
            let body = try await request.body.collect(upTo: 64 * 1024)
            let intent: IntentRequest
            do {
                intent = try JSONDecoder().decode(IntentRequest.self, from: Data(buffer: body))
            } catch {
                return errorResponse(.badRequest, error: "malformed_request")
            }
            do {
                let reply = try await config.replyProvider(intent)
                let latency = Int((Date().timeIntervalSince(started) * 1000).rounded())
                config.requestLogger?.logSuccess(
                    clientId: intent.client_id, text: intent.text, reply: reply, latencyMs: latency
                )
                let payload = IntentResponse(reply: reply, latency_ms: latency)
                return jsonResponse(.ok, body: payload)
            } catch {
                let latency = Int((Date().timeIntervalSince(started) * 1000).rounded())
                config.requestLogger?.logError(
                    clientId: intent.client_id, text: intent.text,
                    error: "\(error)", latencyMs: latency
                )
                return errorResponse(.serviceUnavailable, error: "backend_unavailable")
            }
        }
        return Application(
            router: router,
            configuration: ApplicationConfiguration(address: .hostname(host, port: port))
        )
    }
}

/// Multipart fields for POST /v1/voice/audio. `audio` is the binary payload,
/// other fields are scalar metadata. Optional `lang_hint` / `max_duration_s`
/// stay nil if the client omits them (spec allows).
struct AudioMultipartRequest: Decodable {
    let audio: Data
    let client_id: String
    let ts: String
    let lang_hint: String?
    let max_duration_s: Double?
}

/// Wire format for POST /v1/voice/audio success response. Snake_case JSON
/// to match the spec (intentional underscore-naming on the properties).
struct AudioResponseDTO: Encodable {
    let text: String
    let lang: String
    let duration_s: Double
    let stt_ms: Int
    let stt_engine: String
    let stt_source: String
}

/// Extract boundary value from a `multipart/form-data; boundary=ABC123` header.
/// Tolerant of extra whitespace and optional quotes.
private func extractBoundary(from contentType: String) -> String? {
    guard let range = contentType.range(of: "boundary=", options: .caseInsensitive) else {
        return nil
    }
    let after = contentType[range.upperBound...]
    let raw = after.split(separator: ";", maxSplits: 1).first.map(String.init) ?? String(after)
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
        return String(trimmed.dropFirst().dropLast())
    }
    return trimmed.isEmpty ? nil : trimmed
}

private func jsonResponse<T: Encodable>(_ status: HTTPResponse.Status, body: T) -> Response {
    let data = (try? JSONEncoder().encode(body)) ?? Data()
    return Response(
        status: status,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: ByteBuffer(data: data))
    )
}

func errorResponse(_ status: HTTPResponse.Status, error: String, extra: [String: Any] = [:]) -> Response {
    var dict: [String: Any] = ["error": error]
    for (k, v) in extra { dict[k] = v }
    let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
    return Response(
        status: status,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: ByteBuffer(data: data))
    )
}
