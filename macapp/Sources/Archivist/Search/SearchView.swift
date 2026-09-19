import SwiftUI
import AppKit

/// Graph-based search: query the GraphStore, show the best matches plus what each
/// is connected to (same_tag/same_category/similar_content) — plan.md section 5/6.
struct SearchView: View {
    let store: GraphStore
    @State private var query: String = ""
    @State private var results: [Node] = []
    @State private var expandedNodeId: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search your files…", text: $query, onCommit: runSearch)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _ in runSearch() }

            List(results) { node in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(node.filename).bold()
                        Spacer()
                        Text(node.category).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(node.summary).font(.caption)
                    if !node.tags.isEmpty {
                        Text(node.tags.map { "#\($0)" }.joined(separator: " "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button(expandedNodeId == node.id ? "Hide related" : "Show related") {
                        expandedNodeId = expandedNodeId == node.id ? nil : node.id
                    }
                    .font(.caption)
                    if expandedNodeId == node.id {
                        relatedView(for: node)
                    }
                }
                .padding(.vertical, 4)
                .onTapGesture(count: 2) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
                }
            }
        }
        .padding()
    }

    private func relatedView(for node: Node) -> some View {
        let related = store.connectedNodes(to: node.id)
        return VStack(alignment: .leading, spacing: 2) {
            if related.isEmpty {
                Text("No related files yet.").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(related) { r in
                    Text("• \(r.filename)").font(.caption2)
                }
            }
        }
        .padding(.leading, 12)
    }

    private func runSearch() {
        // Only the single closest match, not a ranked list — "Show related" still
        // surfaces the graph's connected files for that one match.
        results = store.search(query: query, limit: 1)
    }
}
