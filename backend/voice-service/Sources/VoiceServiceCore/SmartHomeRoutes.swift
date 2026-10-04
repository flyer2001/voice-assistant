import Foundation
import Hummingbird

/// Ручки навыка умного дома: OAuth-связка и Provider API.
///
/// Вынесено из `VoiceServiceApp` отдельным файлом: тут своя предметная
/// область (протокол платформы, авторизация), и смешивать её с маршрутами
/// голосового канала значило бы держать в одном файле две разные истории.
enum SmartHomeRoutes {

    /// Разбор `application/x-www-form-urlencoded`. Форму отдаём и принимаем
    /// сами, поэтому полноценный парсер не нужен.
    static func formFields(_ body: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in body.components(separatedBy: "&") where !pair.isEmpty {
            let parts = pair.components(separatedBy: "=")
            guard let name = parts.first else { continue }
            let value = parts.dropFirst().joined(separator: "=")
            fields[percentDecoded(name)] = percentDecoded(value)
        }
        return fields
    }

    static func percentDecoded(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
    }

    /// Форма логина. Без JS и без стилей: её видит один человек один раз,
    /// при привязке навыка.
    static func authForm(state: String, redirectUri: String, clientId: String) -> String {
        """
        <!doctype html><html lang="ru"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Привязка навыка</title></head>
        <body style="font-family:system-ui;max-width:28rem;margin:4rem auto;padding:0 1rem">
        <h1>Привязка навыка умного дома</h1>
        <form method="post" action="/v1/smart-home/auth">
        <input type="hidden" name="state" value="\(htmlEscaped(state))">
        <input type="hidden" name="redirect_uri" value="\(htmlEscaped(redirectUri))">
        <input type="hidden" name="client_id" value="\(htmlEscaped(clientId))">
        <p><label>Логин<br><input name="login" autocomplete="username"></label></p>
        <p><label>Пароль<br><input name="password" type="password"
           autocomplete="current-password"></label></p>
        <p><button type="submit">Привязать</button></p>
        </form></body></html>
        """
    }

    static func htmlEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func register(router: Router<BasicRequestContext>, config: SmartHomeConfig) {

        router.get("/v1/smart-home/auth") { request, _ -> Response in
            let query = request.uri.queryParameters
            let html = authForm(
                state: query["state"].map(String.init) ?? "",
                redirectUri: query["redirect_uri"].map(String.init) ?? "",
                clientId: query["client_id"].map(String.init) ?? ""
            )
            var response = Response(status: .ok,
                                    body: .init(byteBuffer: ByteBuffer(string: html)))
            response.headers[.contentType] = "text/html; charset=utf-8"
            return response
        }

        router.post("/v1/smart-home/auth") { request, _ -> Response in
            let body = try await request.body.collect(upTo: 16 * 1024)
            let fields = formFields(String(buffer: body))

            guard let code = config.store.issueCode(login: fields["login"] ?? "",
                                                    password: fields["password"] ?? "")
            else {
                // Ни редиректа, ни кода: подсказывать перебору нечего.
                return errorResponse(.unauthorized, error: "bad_credentials")
            }

            let redirect = fields["redirect_uri"] ?? ""
            let state = fields["state"] ?? ""
            let separator = redirect.contains("?") ? "&" : "?"
            var response = Response(status: .found)
            response.headers[.location] = "\(redirect)\(separator)code=\(code)&state=\(state)"
            return response
        }

        router.post("/v1/smart-home/token") { request, _ -> Response in
            let body = try await request.body.collect(upTo: 16 * 1024)
            let fields = formFields(String(buffer: body))
            let clientId = fields["client_id"] ?? ""
            let clientSecret = fields["client_secret"] ?? ""

            let token: OAuthToken?
            switch fields["grant_type"] {
            case "authorization_code":
                token = config.store.exchange(code: fields["code"] ?? "",
                                              clientId: clientId,
                                              clientSecret: clientSecret)
            case "refresh_token":
                token = config.store.refresh(refreshToken: fields["refresh_token"] ?? "",
                                             clientId: clientId,
                                             clientSecret: clientSecret)
            default:
                token = nil
            }

            guard let token else {
                return errorResponse(.badRequest, error: "invalid_grant")
            }

            let json = """
            {"access_token":"\(token.accessToken)",\
            "refresh_token":"\(token.refreshToken)",\
            "token_type":"bearer",\
            "expires_in":\(token.expiresIn)}
            """
            var response = Response(status: .ok,
                                    body: .init(byteBuffer: ByteBuffer(string: json)))
            response.headers[.contentType] = "application/json"
            return response
        }
    }
}
