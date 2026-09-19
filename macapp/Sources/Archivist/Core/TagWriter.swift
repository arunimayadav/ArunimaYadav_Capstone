import Foundation

/// Mirrors the graph's own tags onto the file as native macOS Finder tags, so the
/// organization is visible in Finder/Spotlight outside the app — plan.md section 6/8.
enum TagWriter {
    /// macOS's 7 predefined color tags, in the classic Finder Label order (this
    /// ordering is long-standing/well-documented AppleScript "label index" order).
    /// Finder's sidebar entries under Tags ("Red", "Yellow", ...) are saved searches
    /// matching files whose tag NAME is exactly one of these strings — clicking
    /// "Yellow" does not look at the separate labelNumber attribute at all. So to
    /// make a file findable that way, one of these names has to actually be added
    /// as a real tag, not just implied by a color-only attribute.
    private static let labelColorNames = ["Gray", "Green", "Purple", "Blue", "Yellow", "Red", "Orange"]

    @discardableResult
    static func write(category: String, tags: [String], to url: URL) -> Bool {
        let colorIndex = colorLabel(for: category) // 1-7
        let colorName = labelColorNames[colorIndex - 1]

        // De-duplicated: the AI's own "tags" list can legitimately repeat the
        // category (e.g. category="Finance" and tags=["Finance", "Bank Statement"]),
        // and Finder shouldn't show the same tag label twice. The color name is
        // added as a genuine tag (see labelColorNames above) alongside the
        // descriptive ones, specifically so Finder's sidebar color filters work.
        var seen = Set<String>()
        let finderTags = ([category] + tags + [colorName]).filter { seen.insert($0).inserted }
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

        // labelNumber is the classic, fully public/documented Finder color-label
        // resource key (distinct from tag names) — it's what actually produces the
        // colored dot in icon/list view. Set to the same index as colorName above,
        // so the dot's color and the sidebar tag name always agree.
        do {
            var mutableURL = url
            var values = URLResourceValues()
            values.labelNumber = colorIndex
            try mutableURL.setResourceValues(values)
        } catch {
            print("[Archivist][TagWriter] FAILED to set Finder label color for \(url.path): \(error)")
            success = false
        }

        return success
    }

    /// Deterministic so the same category always gets the same color across files —
    /// that consistency is what makes color-grouping in Finder actually useful.
    /// 1-7 are Finder's seven label colors.
    private static func colorLabel(for category: String) -> Int {
        let hash = category.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return (hash % 7) + 1
    }
}
