import Foundation

struct BackendClient {
    let config: Config

    struct UploadResult: Decodable {
        let text: String
        let lang: String?
        let duration_s: Double?
        let stt_ms: Int?
    }

    enum UploadError: Error {
        case httpStatus(Int, String)
        case invalidResponse
    }

    func uploadAudio(fileURL: URL, langHint: String = "ru") async throws -> UploadResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: config.backendURL.appendingPathComponent("/v1/voice/audio"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.backendToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        let ts = ISO8601DateFormatter().string(from: Date())
        let body = buildMultipart(
            boundary: boundary,
            fields: [
                ("client_id", config.clientId),
                ("ts", ts),
                ("lang_hint", langHint),
            ],
            fileField: "audio",
            filename: fileURL.lastPathComponent,
            fileContentType: "audio/wav",
            fileData: audioData
        )

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else { throw UploadError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw UploadError.httpStatus(http.statusCode, raw)
        }
        return try JSONDecoder().decode(UploadResult.self, from: data)
    }

    private func buildMultipart(
        boundary: String,
        fields: [(String, String)],
        fileField: String,
        filename: String,
        fileContentType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        let lf = "\r\n"
        for (key, value) in fields {
            body.append("--\(boundary)\(lf)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\(lf)\(lf)".data(using: .utf8)!)
            body.append("\(value)\(lf)".data(using: .utf8)!)
        }
        body.append("--\(boundary)\(lf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\(lf)".data(using: .utf8)!)
        body.append("Content-Type: \(fileContentType)\(lf)\(lf)".data(using: .utf8)!)
        body.append(fileData)
        body.append("\(lf)--\(boundary)--\(lf)".data(using: .utf8)!)
        return body
    }
}
