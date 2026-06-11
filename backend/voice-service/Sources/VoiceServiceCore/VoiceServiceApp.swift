import Foundation
import Hummingbird

public enum VoiceServiceApp {
    /// Build an Application configured for tests (`.router` transport) or for
    /// production (`.live` listening on host:port). Caller picks the transport
    /// when invoking `app.test(...)` or `app.run()`.
    public static func make(config: Configuration, host: String = "127.0.0.1", port: Int = 8089) -> some ApplicationProtocol {
        let router = Router()
        router.add(middleware: BearerAuthMiddleware(token: config.token))
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
