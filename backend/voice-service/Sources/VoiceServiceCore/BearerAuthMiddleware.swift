import Foundation
import Hummingbird

/// Validates Bearer token in Authorization header. Reject paths under
/// /v1/voice/* if header missing or mismatch — `{"error":"unauthorized"}`
/// with HTTP 401 per backend-protocol.md.
public struct BearerAuthMiddleware<Context: RequestContext>: RouterMiddleware {
    public typealias Input = Request
    public typealias Output = Response

    let token: String

    public init(token: String) {
        self.token = token
    }

    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        guard let header = request.headers[.authorization],
              header == "Bearer \(token)"
        else {
            return errorResponse(.unauthorized, error: "unauthorized")
        }
        return try await next(request, context)
    }
}
