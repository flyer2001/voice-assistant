import Foundation
import Hummingbird

/// Validates Bearer token in Authorization header. Reject paths under
/// /v1/voice/* if header missing or mismatch — `{"error":"unauthorized"}`
/// with HTTP 401 per backend-protocol.md.
public struct BearerAuthMiddleware<Context: RequestContext>: RouterMiddleware {
    public typealias Input = Request
    public typealias Output = Response

    let token: String
    /// Префиксы, которые проверять не надо. Нужен для навыка Алисы:
    /// Яндекс шлёт запросы сам и заголовок Authorization не добавляет,
    /// поэтому там своя защита — секрет в пути плюс сверка skill_id.
    let exemptPrefixes: [String]

    public init(token: String, exemptPrefixes: [String] = []) {
        self.token = token
        self.exemptPrefixes = exemptPrefixes
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let path = request.uri.path
        if exemptPrefixes.contains(where: { path.hasPrefix($0) }) {
            return try await next(request, context)
        }
        guard let header = request.headers[.authorization],
              header == "Bearer \(token)"
        else {
            return errorResponse(.unauthorized, error: "unauthorized")
        }
        return try await next(request, context)
    }
}
