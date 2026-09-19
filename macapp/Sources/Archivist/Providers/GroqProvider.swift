import Foundation

/// Cloud provider, keyed. https://console.groq.com/keys
/// OpenAI-compatible chat API. No embeddings endpoint — embed() throws .notConfigured
/// so ProviderRouter falls back to another provider for that one call.
final class GroqProvider: AIProvider {
    let kind: ProviderKind = .groq
    private let apiKey: String
    private let model: String
    private let baseURL = URL(string: "https://api.groq.com/openai/v1")!

    init(apiKey: String, model: String = "llama-3.3-70b-versatile") {
        self.apiKey = apiKey
        self.model = model
    }

    func understand(excerpt: String, filename: String, existingTags: [String]) async throws -> FileUnderstanding {
        let prompt = PromptBuilder.understandingPrompt(excerpt: excerpt, filename: filename, existingTags: existingTags)
        let raw = try await chat(prompt: prompt)
        return try decodeUnderstanding(raw)
    }

    func interpretCommand(_ text: String) async throws -> ParsedCommand {
        let raw = try await chat(prompt: PromptBuilder.commandPrompt(text))
        return try decodeCommand(raw)
    }

    func embed(text: String) async throws -> [Float] {
        throw ProviderError.notConfigured
    }

    private func chat(prompt: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": prompt]]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTP(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ProviderError.badResponse
        }
        return content
    }

    static func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.requestFailed(body)
        }
    }
}
