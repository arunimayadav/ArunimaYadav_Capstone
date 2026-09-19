import Foundation

enum ProviderKind: String, CaseIterable, Codable, Identifiable {
    case ollama, openai, anthropic, groq, gemini
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama (local)"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .groq: return "Groq"
        case .gemini: return "Gemini"
        }
    }

    var requiresAPIKey: Bool { self != .ollama }

    /// Groq and Anthropic don't expose an embeddings endpoint (as of this writing) —
    /// embedding calls always fall back to Ollama or an embedding-capable cloud provider.
    var supportsEmbeddings: Bool {
        switch self {
        case .ollama, .openai, .gemini: return true
        case .anthropic, .groq: return false
        }
    }
}

enum ProviderError: Error {
    case notConfigured
    case requestFailed(String)
    case badResponse
}

/// A single AI backend capable of the four calls the pipeline needs.
/// Implementations: Ollama (local, default/fallback) and OpenAI/Anthropic/Groq/Gemini
/// (cloud, keyed) — see plan.md section 6/9.
protocol AIProvider {
    var kind: ProviderKind { get }
    func understand(excerpt: String, filename: String, existingTags: [String]) async throws -> FileUnderstanding
    func embed(text: String) async throws -> [Float]
    func interpretCommand(_ text: String) async throws -> ParsedCommand
}

/// Shared prompt-building so every provider asks the same question the same way.
enum PromptBuilder {
    static func understandingPrompt(excerpt: String, filename: String, existingTags: [String]) -> String {
        """
        You are a file-organization assistant. Given a file's name and a text excerpt,
        return STRICT JSON only, no prose, matching this shape:
        {"category": string, "summary": string, "tags": [string], "confidence": number between 0 and 1, "reasoning": string}

        Rules:
        - "category" is a short bucket like "Finance", "Receipts", "Contracts", "Reading", "Personal", "Work".
        - "summary" is one or two plain-language sentences about what this file actually is.
        - "tags" should reuse from this existing vocabulary when it fits: \(existingTags.joined(separator: ", "))
          Only invent a new tag if nothing existing fits. Prefer 1-4 tags.
        - "confidence" reflects how sure you are about category+tags given the excerpt length/quality.

        Filename: \(filename)
        Excerpt:
        \(excerpt.prefix(4000))
        """
    }

    static func commandPrompt(_ text: String) -> String {
        """
        You are a file-organization assistant. The user gave this instruction about
        organizing files already indexed in their system:
        "\(text)"

        Return STRICT JSON only, no prose, matching this shape:
        {"destinationFolderName": string, "searchQuery": string}

        "destinationFolderName" is a short, filesystem-safe folder name capturing their intent.
        "searchQuery" is the plain-language topic to search their file index for (e.g. "bank statements").
        """
    }

    /// Best-effort JSON extraction: some models wrap JSON in prose or code fences.
    static func extractJSON(from raw: String) -> Data? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        return text.data(using: .utf8)
    }
}

struct UnderstandingJSON: Decodable {
    var category: String
    var summary: String
    var tags: [String]
    var confidence: Double
    var reasoning: String
}

struct CommandJSON: Decodable {
    var destinationFolderName: String
    var searchQuery: String
}

extension AIProvider {
    func decodeUnderstanding(_ raw: String) throws -> FileUnderstanding {
        guard let data = PromptBuilder.extractJSON(from: raw) else { throw ProviderError.badResponse }
        let parsed = try JSONDecoder().decode(UnderstandingJSON.self, from: data)
        return FileUnderstanding(category: parsed.category, summary: parsed.summary, tags: parsed.tags,
                                  confidence: parsed.confidence, reasoning: parsed.reasoning)
    }

    func decodeCommand(_ raw: String) throws -> ParsedCommand {
        guard let data = PromptBuilder.extractJSON(from: raw) else { throw ProviderError.badResponse }
        let parsed = try JSONDecoder().decode(CommandJSON.self, from: data)
        return ParsedCommand(destinationFolderName: parsed.destinationFolderName, searchQuery: parsed.searchQuery)
    }
}
