import Foundation

/// Local, default/fallback provider — no API key, no data leaves the machine.
/// Talks to a locally running Ollama daemon (`ollama serve`, default port 11434).
final class OllamaProvider: AIProvider {
    let kind: ProviderKind = .ollama
    private let baseURL: URL
    private let chatModel: String
    private let embedModel: String

    init(baseURL: URL = URL(string: "http://localhost:11434")!,
         chatModel: String = "llama3.1:8b",
         embedModel: String = "nomic-embed-text") {
        self.baseURL = baseURL
        self.chatModel = chatModel
        self.embedModel = embedModel
    }

    func understand(excerpt: String, filename: String, existingTags: [String]) async throws -> FileUnderstanding {
        let prompt = PromptBuilder.understandingPrompt(excerpt: excerpt, filename: filename, existingTags: existingTags)
        let raw = try await generate(prompt: prompt)
        return try decodeUnderstanding(raw)
    }

    func interpretCommand(_ text: String) async throws -> ParsedCommand {
        let raw = try await generate(prompt: PromptBuilder.commandPrompt(text))
        return try decodeCommand(raw)
    }

    func embed(text: String) async throws -> [Float] {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/embeddings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": embedModel,
            "prompt": String(text.prefix(4000))
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTP(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vector = json["embedding"] as? [Double] else {
            throw ProviderError.badResponse
        }
        return vector.map { Float($0) }
    }

    private func generate(prompt: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": chatModel,
            "prompt": prompt,
            "stream": false,
            "format": "json"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTP(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["response"] as? String else {
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
