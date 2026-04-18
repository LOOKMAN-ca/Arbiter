import Foundation

// MARK: — Claude API Client

enum ClaudeClient {

    // MARK: Streaming call

    static func stream(
        messages: [[String: Any]],
        system:   String?,
        apiKey:   String,
        model:    String,
        onToken:  @escaping @Sendable (String) -> Void
    ) async throws -> String {

        var request = try buildRequest(apiKey: apiKey)
        var body: [String: Any] = [
            "model":      model,
            "max_tokens": 2048,
            "stream":     true,
            "messages":   messages,
        ]
        if let sys = system { body["system"] = sys }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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

            guard let jsonData = raw.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { continue }

            if let type = event["type"] as? String,
               type == "content_block_delta",
               let delta = event["delta"] as? [String: Any],
               (delta["type"] as? String) == "text_delta",
               let text = delta["text"] as? String {
                full += text
                onToken(full)
            }
        }

        if full.isEmpty { throw ArbiterError.emptyResponse }
        return full
    }

    // MARK: Non-streaming (used for validation only)

    static func call(
        messages: [[String: Any]],
        system:   String?,
        apiKey:   String,
        model:    String = ModelCatalog.claude.first!.id
    ) async throws -> String {

        var request = try buildRequest(apiKey: apiKey)
        var body: [String: Any] = [
            "model":      model,
            "max_tokens": 800,
            "messages":   messages,
        ]
        if let sys = system { body["system"] = sys }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ArbiterError.networkUnavailable
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ArbiterError.httpError(http.statusCode, String(msg.prefix(200)))
        }

        guard let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text    = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else { throw ArbiterError.emptyResponse }

        return text
    }

    // MARK: Shared request builder

    private static func buildRequest(apiKey: String) throws -> URLRequest {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ArbiterError.parseError("Invalid URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01",        forHTTPHeaderField: "anthropic-version")
        if !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        req.timeoutInterval = 120
        return req
    }
}
