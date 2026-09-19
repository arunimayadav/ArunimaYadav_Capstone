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
///
/// The two skill files below are embedded verbatim (read fresh off disk by
/// SkillLoader, not paraphrased into this Swift string) so this prompt is always
/// governed by whatever skills/tagging.md and skills/filename-nomenclature.md
/// currently say. tagging.md directly governs the "tags" field. Naming itself
/// (pattern assembly + collision handling) is deterministic and implemented in
/// FilenameNomenclature.swift, not by the model — but that code needs
/// ownership/category/docType/title as inputs (see filename-nomenclature.md's own
/// "Input" section), so this call is what supplies those judgment calls.
enum PromptBuilder {
    static func understandingPrompt(excerpt: String, filename: String, existingTags: [String]) -> String {
        """
        You are a file-organization assistant. Given a file's name and a text excerpt,
        return STRICT JSON only, no prose, matching this shape:
        {"ownership": "own" or "other", "category": string, "docType": string, "title": string, "summary": string, "tags": [string], "confidence": number between 0 and 1, "reasoning": string}

        === Tagging skill (governs the "tags" field — follow it exactly) ===
        \(SkillLoader.tagging)
        === end tagging skill ===

        Existing tag vocabulary, per Step 1 of the tagging skill above — try these first: \(existingTags.joined(separator: ", "))

        === Filename skill (governs "ownership", "category", "docType", "title" — \
        these become the Input to a separate naming step, follow the skill's own \
        definitions of each field exactly) ===
        \(SkillLoader.filenameNomenclature)
        === end filename skill ===

        Additional rules for fields the skills above don't fully pin down:
        - "ownership": "own" if this is the archive owner's own authored work
          (an essay, an assignment, personal writing); "other" if it's something
          they received or downloaded from someone else (a lecture deck, a reading,
          an invoice, a statement).
        - "title": a short, clean version of the file's actual subject (2-5 words,
          no punctuation) — this is title_source distilled, per the filename skill's Input.
        - "summary" is one or two plain-language sentences about what this file actually is,
          independent of category/tags.
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
    var ownership: String
    var category: String
    var docType: String
    var title: String
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
        return FileUnderstanding(ownership: parsed.ownership, category: parsed.category, docType: parsed.docType,
                                  title: parsed.title, summary: parsed.summary, tags: parsed.tags,
                                  confidence: parsed.confidence, reasoning: parsed.reasoning)
    }

    func decodeCommand(_ raw: String) throws -> ParsedCommand {
        guard let data = PromptBuilder.extractJSON(from: raw) else { throw ProviderError.badResponse }
        let parsed = try JSONDecoder().decode(CommandJSON.self, from: data)
        return ParsedCommand(destinationFolderName: parsed.destinationFolderName, searchQuery: parsed.searchQuery)
    }
}
