import Foundation

/// Picks cloud-if-configured-else-Ollama for chat calls, and always routes embeddings
/// to whichever configured provider actually supports them — see plan.md section 8/9
/// ("Dual AI backend... embedding calls fall back to Ollama even when a cloud key is
/// set for text generation" if that cloud provider has no embeddings endpoint).
final class ProviderRouter {
    private let settings: SettingsStore
    private let ollama = OllamaProvider()

    init(settings: SettingsStore) {
        self.settings = settings
    }

    private func cloudProvider() -> AIProvider? {
        guard let kind = settings.preferredProvider, kind != .ollama,
              let key = settings.apiKey(for: kind), !key.isEmpty else {
            return nil
        }
        switch kind {
        case .openai: return OpenAIProvider(apiKey: key)
        case .anthropic: return AnthropicProvider(apiKey: key)
        case .groq: return GroqProvider(apiKey: key)
        case .gemini: return GeminiProvider(apiKey: key)
        case .ollama: return nil
        }
    }

    /// Cloud provider if configured, else local Ollama.
    private func primary() -> AIProvider {
        cloudProvider() ?? ollama
    }

    func understand(excerpt: String, filename: String, existingTags: [String]) async -> (FileUnderstanding, String) {
        let provider = primary()
        do {
            let result = try await provider.understand(excerpt: excerpt, filename: filename, existingTags: existingTags)
            return (result, provider.kind.rawValue)
        } catch {
            guard provider.kind != .ollama else {
                return (Self.fallbackUnderstanding(error: error), "none")
            }
            do {
                let result = try await ollama.understand(excerpt: excerpt, filename: filename, existingTags: existingTags)
                return (result, "ollama (fallback)")
            } catch {
                return (Self.fallbackUnderstanding(error: error), "none")
            }
        }
    }

    func interpretCommand(_ text: String) async throws -> ParsedCommand {
        let provider = primary()
        do {
            return try await provider.interpretCommand(text)
        } catch {
            guard provider.kind != .ollama else { throw error }
            return try await ollama.interpretCommand(text)
        }
    }

    /// Routes to the first configured provider that actually supports embeddings.
    func embed(text: String) async -> [Float]? {
        var candidates: [AIProvider] = [ollama]
        if let cloud = cloudProvider(), cloud.kind.supportsEmbeddings {
            candidates.insert(cloud, at: 0)
        }
        for provider in candidates {
            guard provider.kind.supportsEmbeddings else { continue }
            if let vector = try? await provider.embed(text: text) {
                return vector
            }
        }
        return nil
    }

    /// A file that couldn't be understood at all (both providers down) lands in the
    /// review queue rather than being silently guessed at — see plan.md section 8.
    private static func fallbackUnderstanding(error: Error) -> FileUnderstanding {
        FileUnderstanding(category: "Unsorted", summary: "Could not be analyzed automatically.",
                           tags: [], confidence: 0, reasoning: "AI call failed: \(error)")
    }
}
