import Foundation

/// Cloud provider, keyed. https://aistudio.google.com/apikey
final class GeminiProvider: AIProvider {
    let kind: ProviderKind = .gemini
    private let apiKey: String
    private let chatModel: String
    private let embedModel: String
    private let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    init(apiKey: String, chatModel: String = "gemini-1.5-flash", embedModel: String = "text-embedding-004") {
        self.apiKey = apiKey
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
        let url = baseURL.appendingPathComponent("/models/\(embedModel):embedContent").appending(queryItems: [
            URLQueryItem(name: "key", value: apiKey)
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "models/\(embedModel)",
            "content": ["parts": [["text": String(text.prefix(4000))]]]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTP(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embedding = json["embedding"] as? [String: Any],
              let values = embedding["values"] as? [Double] else {
            throw ProviderError.badResponse
        }
        return values.map { Float($0) }
    }

    private func generate(prompt: String) async throws -> String {
        let url = baseURL.appendingPathComponent("/models/\(chatModel):generateContent").appending(queryItems: [
            URLQueryItem(name: "key", value: apiKey)
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["responseMimeType": "application/json"]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkHTTP(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
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
