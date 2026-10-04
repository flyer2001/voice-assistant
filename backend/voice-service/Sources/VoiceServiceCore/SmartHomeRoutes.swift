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

    /// Пути внутри префикса. Без префикса получаются прежние адреса, так
    /// что старые настройки в консоли не ломаются.
    static let authPath = "/auth"
    static let tokenPath = "/token"
    static let announcePath = "/announce"

    /// Форма логина. Без JS и без стилей: её видит один человек один раз,
    /// при привязке навыка.
    static func authForm(state: String, redirectUri: String, clientId: String,
                         action: String) -> String {
        """
        <!doctype html><html lang="ru"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Привязка навыка</title></head>
        <body style="font-family:system-ui;max-width:28rem;margin:4rem auto;padding:0 1rem">
        <h1>Привязка навыка умного дома</h1>
        <form method="post" action="\(action)">
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

    /// Токен платформы из заголовка. Яндекс присылает тот, что получил на
    /// шаге обмена кода.
    static func bearer(_ request: Request) -> String? {
        guard let header = request.headers[.authorization],
              header.lowercased().hasPrefix("bearer ") else { return nil }
        return String(header.dropFirst("bearer ".count))
    }

    /// `request_id` платформа сопоставляет с запросом. Берём из заголовка,
    /// своё значение сломало бы связку тихо.
    static func requestId(_ request: Request) -> String {
        request.headers[.init("X-Request-Id")!] ?? ""
    }

    /// Идентификаторы устройств из тела запроса — и у `query`, и у `action`
    /// формат разный, поэтому путь к ним передаётся параметром.
    static func deviceIds(json: Data, nested: Bool) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        else { return [] }
        let container = nested ? (root["payload"] as? [String: Any]) : root
        let devices = container?["devices"] as? [[String: Any]] ?? []
        return devices.compactMap { $0["id"] as? String }
    }

    /// Запрошенное состояние лампочки из тела `action`.
    static func requestedOnOff(json: Data) -> Bool? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              let devices = payload["devices"] as? [[String: Any]],
              let capabilities = devices.first?["capabilities"] as? [[String: Any]],
              let state = capabilities.first?["state"] as? [String: Any],
              let value = state["value"] as? Bool
        else { return nil }
        return value
    }

    static func json(_ body: String, status: HTTPResponse.Status = .ok) -> Response {
        var response = Response(status: status,
                                body: .init(byteBuffer: ByteBuffer(string: body)))
        response.headers[.contentType] = "application/json"
        return response
    }

    static func register(router: Router<BasicRequestContext>, config: SmartHomeConfig) {
        let base = config.basePath

        // Проба доступности. Платформа стучит в неё до связки аккаунта,
        // поэтому авторизации тут нет.
        router.on("\(base)/v1.0", method: .head) { _, _ -> Response in
            Response(status: .ok)
        }
        router.get("\(base)/v1.0") { _, _ -> Response in
            Response(status: .ok)
        }

        router.get("\(base)/v1.0/user/devices") { request, _ -> Response in
            guard let token = bearer(request), config.store.isValid(token: token) else {
                return errorResponse(.unauthorized, error: "unauthorized")
            }
            // Лампочка не светит — это переключатель для сценария. Тип
            // light выбран потому, что по нему триггер «изменилось
            // состояние» подтверждён живьём, в отличие от датчиков.
            return json("""
            {"request_id":"\(requestId(request))","payload":{"user_id":"sergey","devices":[\
            {"id":"\(config.deviceId)","name":"\(config.deviceName)",\
            "type":"devices.types.light","capabilities":[\
            {"type":"devices.capabilities.on_off","retrievable":true,"reportable":true}]}]}}
            """)
        }

        router.post("\(base)/v1.0/user/devices/query") { request, _ -> Response in
            guard let token = bearer(request), config.store.isValid(token: token) else {
                return errorResponse(.unauthorized, error: "unauthorized")
            }
            let body = try await request.body.collect(upTo: 64 * 1024)
            let ids = deviceIds(json: Data(buffer: body), nested: false)
            // Отдаём сохранённое состояние, а не вычисленное: опрос может
            // прийти через миллисекунды после гашения.
            let value = config.state.isOn
            let devices = ids.map { id in
                """
                {"id":"\(id)","capabilities":[{"type":"devices.capabilities.on_off",\
                "state":{"instance":"on","value":\(value)}}]}
                """
            }.joined(separator: ",")
            return json("""
            {"request_id":"\(requestId(request))","payload":{"devices":[\(devices)]}}
            """)
        }

        router.post("\(base)/v1.0/user/devices/action") { request, _ -> Response in
            guard let token = bearer(request), config.store.isValid(token: token) else {
                return errorResponse(.unauthorized, error: "unauthorized")
            }
            let body = try await request.body.collect(upTo: 64 * 1024)
            let data = Data(buffer: body)
            let ids = deviceIds(json: data, nested: true)

            let results = ids.map { id -> String in
                // Чужой идентификатор не должен дёргать нашу лампочку.
                guard id == config.deviceId, let value = requestedOnOff(json: data) else {
                    return """
                    {"id":"\(id)","capabilities":[{"type":"devices.capabilities.on_off",\
                    "state":{"instance":"on","action_result":{"status":"ERROR",\
                    "error_code":"DEVICE_NOT_FOUND"}}}]}
                    """
                }
                config.state.set(on: value)
                return """
                {"id":"\(id)","capabilities":[{"type":"devices.capabilities.on_off",\
                "state":{"instance":"on","action_result":{"status":"DONE"}}}]}
                """
            }.joined(separator: ",")

            return json("""
            {"request_id":"\(requestId(request))","payload":{"devices":[\(results)]}}
            """)
        }

        // Постановка сообщения в очередь плюс сигнал на колонку. За нашим
        // токеном: ручка дёргает звук в квартире, открывать её нельзя.
        router.post("\(base)\(announcePath)") { request, _ -> Response in
            struct Announce: Decodable { let text: String; let source: String? }
            let body = try await request.body.collect(upTo: 64 * 1024)
            guard let req = try? JSONDecoder().decode(Announce.self, from: Data(buffer: body)),
                  !req.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                // Звонить без сообщения незачем: человек придёт слушать
                // пустую очередь.
                return errorResponse(.badRequest, error: "empty_text")
            }
            await config.announce(req.text)
            return json("{\"ok\":true}")
        }

        router.post("\(base)/v1.0/user/unlink") { request, _ -> Response in
            guard let token = bearer(request), config.store.isValid(token: token) else {
                return errorResponse(.unauthorized, error: "unauthorized")
            }
            // Навык удалили: токен больше не действителен, и стучать
            // callback'ом в платформу нельзя.
            config.store.unlink()
            return json("{\"request_id\":\"\(requestId(request))\"}")
        }

        router.get("\(base)\(authPath)") { request, _ -> Response in
            let query = request.uri.queryParameters
            let html = authForm(
                state: query["state"].map(String.init) ?? "",
                redirectUri: query["redirect_uri"].map(String.init) ?? "",
                clientId: query["client_id"].map(String.init) ?? "",
                action: "\(base)\(authPath)"
            )
            var response = Response(status: .ok,
                                    body: .init(byteBuffer: ByteBuffer(string: html)))
            response.headers[.contentType] = "text/html; charset=utf-8"
            return response
        }

        router.post("\(base)\(authPath)") { request, _ -> Response in
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

        router.post("\(base)\(tokenPath)") { request, _ -> Response in
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
