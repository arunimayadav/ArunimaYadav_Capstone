import Foundation

/// Implements skills/filename-nomenclature.md's two steps directly. That skill is a
/// deterministic algorithm (pattern selection, then collision resolution), not a
/// judgment call, so it's implemented here as code rather than a second AI call —
/// the AI-judgment inputs it needs (ownership/category/docType/title) come from the
/// same understanding call that also applies skills/tagging.md (see AIProvider's
/// PromptBuilder, which embeds both skill files' text verbatim).
enum FilenameNomenclature {
    struct Input {
        var ownership: String   // "own" or "other"
        var category: String
        var docType: String
        var title: String
        var personName: String  // from Settings config — never inferred from the file
        var fileExtension: String
    }

    /// Step 1 (pick the pattern) + Step 2 (resolve collisions against what's already
    /// in the destination folder) from skills/filename-nomenclature.md.
    static func filename(for input: Input, existingFilenames: Set<String>) -> String {
        let base = baseName(for: input)
        return resolveCollision(base: base, extension: input.fileExtension, existingFilenames: existingFilenames)
    }

    /// Step 1: "If ownership == own: <PersonName>_<Title>_<YYYY-MM-DD>.<ext>.
    /// If ownership == other: <Category>_<Title>_<DocType>.<ext>"
    private static func baseName(for input: Input) -> String {
        let title = collapseToToken(input.title)
        if input.ownership == "own" && !input.personName.isEmpty {
            let date = Self.dateOnlyFormatter.string(from: Date())
            return "\(collapseToToken(input.personName))_\(title)_\(date)"
        } else {
            let category = collapseToToken(input.category)
            let docType = collapseToToken(input.docType)
            return "\(category)_\(title)_\(docType)"
        }
    }

    /// Step 2: "If the generated name already exists... append -2, -3, etc."
    private static func resolveCollision(base: String, extension ext: String, existingFilenames: Set<String>) -> String {
        var candidate = "\(base).\(ext)"
        guard existingFilenames.contains(candidate) else { return candidate }
        var counter = 2
        repeat {
            candidate = "\(base)-\(counter).\(ext)"
            counter += 1
        } while existingFilenames.contains(candidate)
        return candidate
    }

    /// "Remove characters that are invalid or awkward in filenames... leading/trailing
    /// whitespace" and match the skill's own examples (MidtermEssay, DesignThinking,
    /// Lecture2) by joining words with no separator rather than keeping spaces.
    private static func collapseToToken(_ raw: String) -> String {
        raw.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
