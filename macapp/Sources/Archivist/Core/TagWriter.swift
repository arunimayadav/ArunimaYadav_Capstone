import Foundation

/// Mirrors the graph's own tags onto the file as native macOS Finder tags, so the
/// organization is visible in Finder/Spotlight outside the app — plan.md section 6/8.
enum TagWriter {
    static func write(category: String, tags: [String], to url: URL) {
        do {
            // Untyped NSURL API instead of URLResourceValues.tagNames — this SDK marks
            // the typed setter macOS 26+ only, but the underlying resource key works
            // fine on any macOS version that has Finder tags at all.
            try (url as NSURL).setResourceValue([category] + tags, forKey: .tagNamesKey)
        } catch {
            // Non-fatal: the graph record (source of truth) is unaffected either way.
        }
    }
}
