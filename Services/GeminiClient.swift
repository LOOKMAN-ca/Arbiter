import Foundation

// MARK: — Gemini API Client

enum GeminiClient {

    // MARK: Streaming call

    static func stream(
        prompt:  String,
        apiKey:  String,
        model:   String,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {

        let request = try buildRequest(prompt: prompt, apiKey: apiKey, model: model, stream: true)
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ArbiterError.networkUnavailable
        }
        guard http.statusCode == 200 else {
            var errText = ""
            for try await byte in asyncBytes { errText += String(UnicodeScalar(byte)) }
            throw ArbiterError.httpError(http.statusCode, String(errText.prefix(200)))
        }

        var full = ""

        for try await line in asyncBytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let raw = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, raw != "[DONE]" else { continue }

            guard let jsonData  = raw.data(using: .utf8),
                  let event     = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let candidates = event["candidates"] as? [[String: Any]],
                  let first     = candidates.first,
                  let content   = first["content"] as? [String: Any],
                  let parts     = content["parts"] as? [[String: Any]],
                  let text      = parts.first?["text"] as? String
            else { continue }

            full += text
            onToken(full)
        }

        if full.isEmpty { throw ArbiterError.emptyResponse }
        return full
    }

    // MARK: Ping (connection test)

    static func ping(apiKey: String, model: String) async throws {
        let request = try buildRequest(prompt: "Reply OK.", apiKey: apiKey, model: model, stream: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ArbiterError.networkUnavailable
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ArbiterError.httpError(http.statusCode, String(msg.prefix(200)))
        }
    }

    // MARK: Request builder

    private static func buildRequest(
        prompt: String,
        apiKey: String,
        model:  String,
        stream: Bool
    ) throws -> URLRequest {
        let endpoint = stream
            ? "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?key=\(apiKey)&alt=sse"
            : "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"

        guard let url = URL(string: endpoint) else {
            throw ArbiterError.parseError("Invalid Gemini URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature":     0.65,
                "maxOutputTokens": 2048,
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
}
