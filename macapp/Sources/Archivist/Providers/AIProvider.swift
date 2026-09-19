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
/// Only skills/tagging.md is embedded verbatim here (read fresh off disk by
/// SkillLoader) — tagging is a genuine judgment call the model has to make, so it
/// needs the real rules text. skills/filename-nomenclature.md is deliberately NOT
/// embedded: its Step 1/Step 2 (pattern assembly, collision resolution) is
/// deterministic and implemented directly in FilenameNomenclature.swift against
/// the real file, so the model never needs to see that skill's own text — it only
/// supplies the four raw judgment fields (ownership/category/docType/title) that
/// feed into it.
///
/// This split exists because of a confirmed failure mode: embedding
/// filename-nomenclature.md's own worked example ("DesignThinking_Lecture2_Slides.pptx")
/// caused the local model to echo those literal example words as its answer for an
/// unrelated file, instead of reasoning about the actual excerpt — the skill file's
/// illustrative example became a distractor. tagging.md has the same kind of
/// example text (e.g. "not DesignThinking-Week2-Notes"), so it stays, but with an
/// explicit instruction below not to copy from it.
enum PromptBuilder {
    static func understandingPrompt(excerpt: String, filename: String, existingTags: [String]) -> String {
        """
        You are a file-organization assistant. Given a file's name and a text excerpt,
        return STRICT JSON only, no prose, matching this shape:
        {"ownership": "own" or "other", "category": string, "docType": string, "title": string, "summary": string, "tags": [string], "confidence": number between 0 and 1, "reasoning": string}

        === Tagging skill (governs the "tags" field — follow its rules, but never copy
        any example word or phrase from this section itself into your answer; every
        word you output must come only from the actual excerpt below or from the real
        existing tag vocabulary listed after this section) ===
        \(SkillLoader.tagging)
        === end tagging skill ===

        Existing tag vocabulary, per Step 1 of the tagging skill above — try these first: \(existingTags.joined(separator: ", "))

        Field definitions:
        - "ownership": "own" if this is the archive owner's own authored work
          (an essay, an assignment, personal writing); "other" if it's something
          they received or downloaded from someone else (a lecture deck, a reading,
          an invoice, a statement).
        - "category": a short bucket describing what kind of file this is (e.g. Finance,
          Course, Personal, Work) — based only on the excerpt below, never a guess.
        - "docType": a short document type (Essay, Notes, Slides, Reading, Assignment,
          Invoice, Statement, Receipt, etc.) — pick the closest fit to the excerpt below.
        - "title": a short, clean version of THIS file's actual subject (2-5 words, no
          punctuation), describing what the excerpt below is actually about.
        - "summary" is one or two plain-language sentences about what this file actually
          is, independent of category/tags, describing only the excerpt below.
        - "confidence" reflects how sure you are about category+tags given the excerpt length/quality.

        Every field above must be grounded only in the filename and excerpt given below —
        never in any example text from the tagging skill section.

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
