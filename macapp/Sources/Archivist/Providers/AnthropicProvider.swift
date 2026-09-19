import Foundation

/// Cloud provider, keyed. https://console.anthropic.com/settings/keys
/// No embeddings endpoint — embed() always throws .notConfigured so ProviderRouter
/// falls back to Ollama/OpenAI/Gemini for that one call (see plan.md section 9).
final class AnthropicProvider: AIProvider {
    let kind: ProviderKind = .anthropic
    private let apiKey: String
    private let model: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1")!

    init(apiKey: String, model: String = "claude-3-5-haiku-20241022") {
        self.apiKey = apiKey
        self.model = model
    }

    func understand(excerpt: String, filename: String, existingTags: [String]) async throws -> FileUnderstanding {
        let prompt = PromptBuilder.understandingPrompt(excerpt: excerpt, filename: filename, existingTags: existingTags)
        let raw = try await message(prompt: prompt)
        return try decodeUnderstanding(raw)
    }

    func interpretCommand(_ text: String) async throws -> ParsedCommand {
        let raw = try await message(prompt: PromptBuilder.commandPrompt(text))
        return try decodeCommand(raw)
    }

    func embed(text: String) async throws -> [Float] {
        throw ProviderError.notConfigured
    }

    private func message(prompt: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("/messages"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTP(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw ProviderError.badResponse
        }
        return text
    }

    static func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.requestFailed(body)
        }
    }
}
