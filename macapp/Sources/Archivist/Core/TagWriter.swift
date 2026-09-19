import Foundation

/// Mirrors the graph's own tags onto the file as native macOS Finder tags, so the
/// organization is visible in Finder/Spotlight outside the app — plan.md section 6/8.
enum TagWriter {
    @discardableResult
    static func write(category: String, tags: [String], to url: URL) -> Bool {
        // De-duplicated: the AI's own "tags" list can legitimately repeat the
        // category (e.g. category="Finance" and tags=["Finance", "Bank Statement"]),
        // and Finder shouldn't show the same tag label twice.
        var seen = Set<String>()
        let finderTags = ([category] + tags).filter { seen.insert($0).inserted }
        do {
            // Untyped NSURL API instead of URLResourceValues.tagNames — this SDK marks
            // the typed setter macOS 26+ only, but the underlying resource key works
            // fine on any macOS version that has Finder tags at all.
            try (url as NSURL).setResourceValue(finderTags, forKey: .tagNamesKey)
            return true
        } catch {
            print("[Archivist][TagWriter] FAILED to write Finder tags \(finderTags) to \(url.path): \(error)")
            return false
        }
    }
}
