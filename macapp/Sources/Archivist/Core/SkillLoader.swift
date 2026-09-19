import Foundation

/// Reads skills/*.md straight from the repo at runtime, so the AI prompt is built
/// from the actual current text of those files rather than a paraphrase of their
/// rules hardcoded into Swift that could silently drift out of sync.
///
/// `#filePath` embeds this source file's absolute path at compile time; this is a
/// locally-run capstone tool, not a distributed binary, so resolving skills/ relative
/// to the checked-out repo (rather than bundling copies into the app) is the simplest
/// way to guarantee the running app is always reading the same file a person editing
/// skills/tagging.md or skills/filename-nomenclature.md would see.
enum SkillLoader {
    private static let repoRoot: URL = {
        // #filePath = <repo>/macapp/Sources/Archivist/Core/SkillLoader.swift — strip
        // the filename itself plus 4 directories (Core, Archivist, Sources, macapp)
        // to land on <repo>, not <repo>/macapp.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SkillLoader.swift -> Core
            .deletingLastPathComponent() // Core -> Archivist
            .deletingLastPathComponent() // Archivist -> Sources
            .deletingLastPathComponent() // Sources -> macapp
            .deletingLastPathComponent() // macapp -> repo root
    }()

    static var filenameNomenclature: String { load("skills/filename-nomenclature.md") }
    static var tagging: String { load("skills/tagging.md") }

    private static func load(_ relativePath: String) -> String {
        let url = repoRoot.appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            print("[Archivist][SkillLoader] could not read \(url.path) — proceeding without it")
            return ""
        }
        return text
    }
}
