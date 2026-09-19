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
        var success = true
        do {
            // Untyped NSURL API instead of URLResourceValues.tagNames — this SDK marks
            // the typed setter macOS 26+ only, but the underlying resource key works
            // fine on any macOS version that has Finder tags at all.
            try (url as NSURL).setResourceValue(finderTags, forKey: .tagNamesKey)
        } catch {
            print("[Archivist][TagWriter] FAILED to write Finder tags \(finderTags) to \(url.path): \(error)")
            success = false
        }

        // Tag *names* alone are real and searchable (confirmed via `xattr -l`), but
        // a brand-new tag has no color assigned, so it shows no colored dot in
        // Finder's default icon view — easy to mistake for "not tagged at all" even
        // though the data is there. `labelNumber` is the classic, fully public/
        // documented Finder color-label resource key (distinct from tag names) and
        // reliably produces a visible colored dot, so it's set here too.
        do {
            var mutableURL = url
            var values = URLResourceValues()
            values.labelNumber = colorLabel(for: category)
            try mutableURL.setResourceValues(values)
        } catch {
            print("[Archivist][TagWriter] FAILED to set Finder label color for \(url.path): \(error)")
            success = false
        }

        return success
    }

    /// Deterministic so the same category always gets the same color across files —
    /// that consistency is what makes color-grouping in Finder actually useful.
    /// 1-7 are Finder's seven label colors; 0 is "no color."
    private static func colorLabel(for category: String) -> Int {
        let hash = category.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return (hash % 7) + 1
    }
}
